#!/usr/bin/perl -W

use strict;
use warnings;
use DBI;
use Switch;
use Text::Table;

# user editable variables begin
my $dbfile = './cables.db';
# user editable variables end

my $dbh;

sub init_db() {
  $dbh->do("CREATE TABLE device_type(id INTEGER PRIMARY KEY, name TEXT)");
  $dbh->do("CREATE TABLE room(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, description TEXT)");
  $dbh->do("CREATE TABLE rack(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, description TEXT, room_id INT, CONSTRAINT room_id_fk FOREIGN KEY(room_id) REFERENCES room(id))");
  $dbh->do("CREATE TABLE device(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, description TEXT, rack_id INT, FOREIGN KEY(rack_id) REFERENCES rack(id))");
  $dbh->do("CREATE TABLE interface_type(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)");
  $dbh->do("CREATE TABLE interface(id INTEGER PRIMARY KEY AUTOINCREMENT, interface_type_id INT, device_id INT, FOREIGN KEY(interface_type_id) REFERENCES interface_type(id), FOREIGN KEY(device_id) REFERENCES device(id))");
  $dbh->do("CREATE TABLE connection_type(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)");
  $dbh->do("CREATE TABLE connection(".
    "id INTEGER PRIMARY KEY AUTOINCREMENT, from_interface_id INT, to_interface_id INT, connection_type_id INT, ".
    "CONSTRAINT connection_type_id_fk FOREIGN KEY(connection_type_id) REFERENCES connection_type(id), ".
    "CONSTRAINT from_interface_id_fk FOREIGN KEY(from_interface_id) REFERENCES interface(id), ".
    "CONSTRAINT to_interface_id_fk FOREIGN KEY(to_interface_id) REFERENCES interface(id))");
}

sub print_help() {
    print "Help!\n";
}

sub print_help_list() {
    print "Help! List!\n";
}

my $dsn = "dbi:SQLite:dbname=$dbfile";
my $doinit = 0;

if (! -f $dbfile) {
  $doinit = 1;
}

$dbh = DBI->connect($dsn, "", "", { RaiseError => 1 })
  or die $DBI::errstr;
$dbh->do("PRAGMA foreign_keys = ON");

if ($doinit == 1) {
  init_db();
}

my $sth;
my $table;
my $command = shift;
if ($command) {
    switch ($command) {
	case "list" {
	    my $subcommand = shift;
	    if (!$subcommand) {
		print_help_list();
	    } else {
		switch ($subcommand) {
		    case "room" {
			$sth = $dbh->prepare("SELECT * FROM room");
			$table = Text::Table->new("ID", "Name", "Description");
		    }
		}
	    }
	}
	else { print_help(); }
    }
} else {
    print_help();
}

if ($sth) {
    $sth->execute();
    my $row;
    while ($row = $sth->fetchrow_arrayref()) {
	$table->load($row);
    }
    print $table;
    $sth->finish();
}
$dbh->disconnect();
