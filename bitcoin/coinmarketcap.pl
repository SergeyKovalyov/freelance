#!/usr/bin/env perl
#
# Author: Sergey Kovalyov (sergey.kovalyov@gmail.com)
#
use autodie;
use common::sense;

use Getopt::Long;
use POSIX;
use LWP::UserAgent::Cached;
use HTML::TreeBuilder;
use DBI;
use Time::Piece;
use Readonly;
use IO::Handle;



my %opts;
$opts{tor} = 1;
GetOptions(
	'tor!'      => \$opts{tor},
	'debug'     => \$opts{debug},
	'dev-db'    => \$opts{dev_db},
	'use-cache' => \$opts{use_cache},
	'cache_dir=s' => \$opts{cache_dir},
);
if ($opts{use_cache}) {
	$opts{cache_dir} = 'cache' unless $opts{cache_dir};
	mkdir $opts{cache_dir} unless -d $opts{cache_dir};
}
Readonly %opts => %opts;
Readonly my $ua => LWP::UserAgent::Cached->new(
	agent => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:52.0) Gecko/20100101 Firefox/52.0',
	cache_dir => $opts{cache_dir},
	recache_if => sub {
		my (undef, $path) = @_;
		say "#\tcached filename: $path" if $opts{debug};
		0;
	},
);
$ua->proxy([ qw/http https/ ] => 'socks://localhost:9050') if $opts{tor};
if ($opts{debug}) {
	autoflush STDOUT;
	$ua->show_progress(1);
}



sub dump_data {
	my ($data, $name) = @_;

	say "#\n# $name dump:" if $name;
	foreach (sort keys %$data) {
		say "# $_ = ", $data->{$_} if defined $data->{$_};
	}
	say "#";
}


sub timestamp {
	return strftime "%Y-%m-%d %H:%M:%S", localtime;
}



sub init_db {
	my ($dbh, $user, $pass);

	unless ($opts{dev_db}) {
		$user = 'sergey';
		$pass = 'changeme';
	}
	$dbh = DBI->connect("dbi:mysql:scrape", $user, $pass) or die "Cannot connect: $DBI::errstr";
	$dbh->{PrintError} = 0;
	$dbh->{RaiseError} = 1;

	return $dbh;
}



sub get_url {
	my ($url) = @_;

	say "# getting $url";
	my $resp = $ua->get($url);
	return $resp->decoded_content if $resp->is_success;
	die 'something goes wrong: ', $resp->code;
}



sub insert_data {
	my ($dbh, $data) = @_;

	$dbh->do("insert into coinmarketcap_data ("
		. (join ',', map "`$_`", keys %$data)
		. ") values ("
		. (join ',', map '?', keys %$data)
		. ")", undef, values %$data);
	return $dbh->last_insert_id((undef) x 4);
}



sub parse_row {
	my ($tds) = @_;

	my %row;
	@row{qw/currency currency_pair/} = map { $_->as_text } @$tds[1, 2];
	@row{qw/volume_24 current_price/} = map { $_->attr('data-usd') } @$tds[3, 4];
	if ($row{volume_24} eq '?') {
		die 'unexpected data' unless $tds->[3]->as_text =~ /\$0$/;
		$row{volume_24} = 0;
	}
	return \%row;
}



sub process_exch {
	my ($url) = @_;

	my $content = get_url $url;
	my $tree = HTML::TreeBuilder->new_from_content($content);
	my @res = $tree->look_down(class => 'table no-border table-condensed');
	die 'only one table expected' unless @res == 1;

	my @rows;
	my $table = shift @res;
	for my $row ($table->look_down(_tag => 'tr')) {
		my @tds = $row->look_down(_tag => 'td');
		if (@tds == 0) {
			# skip table headers <th>
			next;
		} elsif (@tds == 7) {
			next if $tds[0]->as_text <= 10;
			my $row = parse_row \@tds;
			push @rows, $row;
		} else {
			die 'unexpected number of columns: ' . @tds;
		}
	}
	$tree->delete;
}



sub main {
	dump_data \%opts, 'options' if $opts{debug};
	say "# ", timestamp(), ": started";
	my $dbh = init_db();

	my $content = get_url 'https://coinmarketcap.com/exchanges/volume/24-hour/all/';
	my $tree = HTML::TreeBuilder->new_from_content($content);
	my @res = $tree->look_down(class => 'table table-condensed');
	die 'only one table expected' unless @res == 1;

	my $table = shift @res;
	my (@exch_rows, $exch_name, $exch_sum);
	die 'No last updated' unless $content =~ /Last updated: (.+UTC)/i;
	my $last_updated_utc = $1;
	$last_updated_utc =~ s/\s+/ /g;

	for my $row ($table->look_down(_tag => 'tr')) {
		my @tds = $row->look_down(_tag => 'td');
		if (@tds == 0) {
			# skip table headers <th>
			# reset volumes sum
			$exch_sum = 0;
			next;
		} elsif (@tds == 4 and $tds[0]->as_text =~ /total/i) {
			# skip Total row
			next;
		} elsif (@tds == 6) {
			my $row = parse_row \@tds;
			$exch_sum += $row->{volume_24};
			$row->{exchange} = $exch_name;
			push @exch_rows, $row;
		} elsif (@tds == 1) {
			my $atag = $tds[0]->look_down(_tag => 'a');
			next unless $atag;

			my $txt = $atag->as_text;
			unless ($txt =~ /View More/i) {
				$exch_name = $txt;
				next;
			}
			# no Volumes on this exch so no need to load details
			next unless $exch_sum;
			my $rows = process_exch 'https://coinmarketcap.com' . $atag->attr('href');
			for $row (@$rows) {
				$row->{exchange} = $exch_name;
				push @exch_rows, $row;
			}
		} else {
			die 'unexpected number of columns: ' . @tds;
		}
	}
	$tree->delete;

	my $tstamp = timestamp();
	my $lu_et = $last_updated_utc;
	$lu_et =~ s/ UTC//i;
	$lu_et = strftime "%Y-%m-%d %H:%M:%S", localtime Time::Piece->strptime($lu_et, "%b %d, %Y %I:%M %p")->epoch;

	$dbh->begin_work;
	for my $row (@exch_rows) {
		# we don't need these pairs data
		next if $row->{currency_pair} eq 'BTC/USD' or $row->{currency_pair} eq 'BTC/USDT';
		next unless $row->{volume_24};

		$row->{gathered_at_et} = $tstamp;
		$row->{last_updated_utc} = $last_updated_utc;
		$row->{last_updated_et} = $lu_et;
		insert_data $dbh, $row;
	}
	$dbh->commit;

	say "# ", timestamp(), ": exit";
	exit;
}

main();

