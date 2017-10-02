#!/usr/bin/env perl
#
# Author: Sergey Kovalyov (sergey.kovalyov@gmail.com)
#
use autodie;
use common::sense;

use Getopt::Long;
use POSIX;
use LWP::UserAgent::Cached;
use JSON::XS qw/decode_json/;
use Encode qw/encode_utf8/;
use DBI;
use Readonly;
use IO::Handle;



my %opts;
$opts{tor} = 1;
GetOptions(
	'tor!'      => \$opts{tor},
	'alter'     => \$opts{alter},
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



sub create_template_tbl {
	my ($dbh, $name) = @_;

	$dbh->do("create table if not exists $name (
			id int unsigned auto_increment primary key,
			created_at timestamp not null default current_timestamp on update current_timestamp, key(created_at)
		) engine = InnoDB");
}



sub init_db {
	my ($dbh, $user, $pass);

	unless ($opts{dev_db}) {
		$user = 'sergey';
		$pass = 'changeme';
	}
	$dbh = DBI->connect("dbi:mysql:nfl_stats", $user, $pass) or die "Cannot connect: $DBI::errstr";
	$dbh->{PrintError} = 0;
	$dbh->{RaiseError} = 1;

	for my $table (qw/games competitors groups outcomes/) {
		create_template_tbl $dbh, $table;
	}
	return $dbh;
}



sub get_url {
	my ($url) = @_;

	say "# getting $url";
	my $resp = $ua->get($url);
	return $resp->decoded_content if $resp->is_success;
	die "something goes wrong: ", $resp->code;
}



sub get_json {
	my ($url, $mark) = @_;

	my $content = get_url $url;
	die unless $content =~ m%$mark = ({"items":.+?})</script>%;
	return decode_json encode_utf8 $1;
}



sub check_columns {
	my ($dbh, $table, $data) = @_;

	return unless $opts{alter};
	my %columns;
	for (@{ $dbh->selectall_arrayref("show columns from $table") }) {
		$columns{ $_->[0] } = 1;
	}
	for (keys %$data) {
		next if $columns{$_};
		$dbh->do("alter table $table add `$_` varchar(255) default null");
		say "# alter table $table add $_" if $opts{debug};
	}
}



sub insert_data {
	my ($dbh, $table, $data) = @_;

	check_columns $dbh, $table, $data;
	$dbh->do("insert into $table ("
		. (join ',', map "`$_`", keys %$data)
		. ") values ("
		. (join ',', map '?', keys %$data)
		. ")", undef, values %$data);
	return $dbh->last_insert_id((undef) x 4);
}



sub process_game {
	my ($dbh, $game) = @_;

	$game->{link} = 'https://sports.bovada.lv' . $game->{link};
	$game->{id2} = $game->{id};
	# now we don't need these fields
	delete $game->{$_} for qw/displayGroups competitors baseLink atmosphereLink id/;
	$game->{startTime} = strftime "%Y-%m-%d %H:%M:%S", gmtime $game->{startTime} / 1000;
	my ($id) = $dbh->selectrow_array("select id from games where id2 = ?", undef, $game->{id2});
	if ($id) {
		return $id;
	} else {
		return insert_data $dbh, 'games', $game;
	}
}



sub process_competitors {
	my ($dbh, $competitors, $id) = @_;

	for my $comp (@$competitors) {
		$comp->{id2} = $comp->{id};
		# now we don't need these fields
		delete $comp->{$_} for qw/id/;

		$comp->{game_id} = $id;
		my ($c_id) = $dbh->selectrow_array("select id from competitors where id2 = ?", undef, $comp->{id2});
		insert_data $dbh, 'competitors', $comp unless $c_id;;
	}
}



sub process_group_item {
	my ($dbh, $item, $id) = @_;

	$item->{id2} = $item->{id};
	# now we don't need these fields
	delete $item->{$_} for qw/id outcomes/;
	my ($g_id) = $dbh->selectrow_array("select id from groups where id2 = ?", undef, $item->{id2});
	if ($g_id) {
		return $g_id;
	} else {
		return insert_data $dbh, 'groups', $item;
	}
}



sub process_outcomes {
	my ($dbh, $o, $id) = @_;

	my $price = $o->{price};
	$price->{price_id} = $price->{id};
	$o->{id2} = $o->{id};
	# now we don't need these fields
	delete $o->{$_} for qw/id price/;
	delete $price->{$_} for qw/id/;

	$o->{group_id} = $id;
	my $data = { %$o, %$price };
	my ($o_id) = $dbh->selectrow_array("select id from outcomes where id2 = ?", undef, $data->{id2});
	insert_data $dbh, 'outcomes', $data unless $o_id;
}



sub process_groups {
	my ($dbh, $groups, $id) = @_;

	for my $g (@$groups) {
		$g->{game_id} = $id;
		$g->{type_id} = $g->{id};
		$g->{gr_description} = $g->{description};
		for my $item (@{ $g->{itemList} }) {
			my $outs = $item->{outcomes};
			$item->{$_} = $g->{$_} for qw/game_id type_id gr_description/;
			my $group_id = process_group_item $dbh, $item;
			for my $o (@$outs) {
				process_outcomes $dbh, $o, $group_id;
			}
		}
	}
}



sub main {
	dump_data \%opts, 'options' if $opts{debug};
	say "# ", strftime "%Y-%m-%d %H:%M:%S: started", localtime;
	my $dbh = init_db();

	for my $url (qw{
			https://sports.bovada.lv/football/nfl/game-lines-market-group
			https://sports.bovada.lv/football/nfl/quarterback-props-market-group
			https://sports.bovada.lv/football/nfl/rushing-props-market-group
			https://sports.bovada.lv/football/nfl/receiving-props-market-group
			https://sports.bovada.lv/football/nfl/touchdown-and-field-goal-props-market-group
			https://sports.bovada.lv/football/nfl/defense-special-teams-props-market-group
			https://sports.bovada.lv/football/nfl/futures-market-group
			https://sports.bovada.lv/football/cfl/game-lines-market-group
			https://sports.bovada.lv/football/cfl/futures-market-group
			https://sports.bovada.lv/football/college/game-lines-market-group
			https://sports.bovada.lv/football/college/futures-market-group
			https://sports.bovada.lv/football/nfl-season-props
			https://sports.bovada.lv/football/college-season-props
			https://sports.bovada.lv/football/nfl-specials
			}) {
		my $json = get_json $url, 'swc_market_lists';
		$json = $json->{items}[0]{itemList}{items};
		say "# no data for url: $url" unless @$json;

		for my $game (@$json) {
			my $json = get_json 'https://sports.bovada.lv' . $game->{link}, 'swc_game_view';
			$game = $json->{items}[0];

			my $cmps = $game->{competitors};
			my $groups = $game->{displayGroups};

			$dbh->begin_work;
			my $id = process_game $dbh, $game;
			process_competitors $dbh, $cmps, $id;
			process_groups $dbh, $groups, $id;
			$dbh->commit;
		}
	}

	say "# ", strftime "%Y-%m-%d %H:%M:%S: exit", localtime;
	exit;
}

main();

