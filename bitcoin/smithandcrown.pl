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
		my $content = do { open my $fh, '<', $ENV{HOME} . '/.my.cnf'; local $/; <$fh> };
		for (split /\n/, $content) {
			$user = $1 if /user=(.+)/;
			$pass = $1 if /password=(.+)/;
		}
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

	$dbh->do("insert into smith_and_crown_icos ("
		. (join ',', map "`$_`", keys %$data)
		. ") values ("
		. (join ',', map '?', keys %$data)
		. ")", undef, values %$data);
	return $dbh->last_insert_id((undef) x 4);
}



sub parse_date {
	my ($date) = @_;

	return Time::Piece->strptime($date, '%b %d, %Y')->strftime('%Y-%m-%d');
}



sub clean_value {
	my ($t) = @_;

	$t =~ s/\s+/ /g;
	$t =~ s/^\s+//;
	$t =~ s/\s+$//;
	return $t;
}



sub parse_row {
	my ($tds, $tr, $attributes) = @_;

	my %row;
	@row{qw/name report_type description start_date end_date raised/} = map { $_->as_text } @$tds[0 .. 2, 4 .. 6];
	@row{qw/name symbol/} = $row{name} =~ /(.+)\((.*)\)/;
	$row{report} = $tr->attr('data-url') if $row{report_type};
	if ($row{raised} eq '--' or $row{raised} =~ /refunded/i or $row{raised} =~ /canceled/i or $row{raised} =~ m{N/A}i) {
		delete $row{raised};
	} elsif ($row{raised}) {
		$row{raised} =~ s/[ ,\$]//g;
	} else {
		delete $row{raised};
	}
	$row{$_} = clean_value $row{$_} for keys %row;
	$row{$_} = parse_date $row{$_} for qw/start_date end_date/;

	my @d;
	for ($tds->[3]->look_down(_tag => 'img')) {
		my $value = $attributes->{ $_->attr('src') };
		unless ($value) {
			die "unknown attribute: ", $_->attr('src');
			next;
		}
		push @d, $value;
	}
	$row{attributes} = join ';', sort @d;
	return \%row;
}



sub main {
	dump_data \%opts, 'options' if $opts{debug};
	say "# ", timestamp(), ": started";
	my $dbh = init_db();

	my $content = get_url 'https://www.smithandcrown.com/icos/';
	my $tree = HTML::TreeBuilder->new_from_content($content);

	my %attributes;
	for my $attr ($tree->look_down(class => 'legend-item')) {
		my $src = $attr->look_down(_tag => 'img')->attr('src');
		next unless $src;
		$attributes{$src} = clean_value $attr->as_text;
	}

	my @res = $tree->look_down(class => 'table js-tablesorter');
	die 'only two tables expected' unless @res == 2;

	my @data;
	for my $table (@res) {
		for my $row ($table->look_down(_tag => 'tr')) {
			my @tds = $row->look_down(_tag => 'td');
			# skip table headers <th>
			next if @tds == 0;
			die 'unexpected number of columns: ' . @tds unless @tds == 7;
			push @data, parse_row \@tds, $row, \%attributes;
		}
	}
	$tree->delete;

	$dbh->begin_work;
	insert_data $dbh, $_ for @data;
	$dbh->commit;

	say "# ", timestamp(), ": exit";
	exit;
}

main();

