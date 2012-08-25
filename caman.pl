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
  $dbh->do("CREATE TABLE device_type(id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
  $dbh->do("CREATE TABLE room(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK (NOT name = ''), description TEXT, notes TEXT)");
  $dbh->do("CREATE TABLE rack(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK (NOT name = ''), description TEXT, room_id INT, notes TEXT, FOREIGN KEY(room_id) REFERENCES room(id))");
  $dbh->do("CREATE TABLE device(id INTEGER PRIMARY KEY AUTOINCREMENT, device_type_id INT, name TEXT NOT NULL  CHECK (NOT name = ''), description TEXT, rack_id INT, notes TEXT, FOREIGN KEY(rack_id) REFERENCES rack(id), FOREIGN KEY(device_type_id) REFERENCES device_type(id))");
  $dbh->do("CREATE TABLE interface_type(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK (NOT name = ''))");
  $dbh->do("CREATE TABLE interface(id INTEGER PRIMARY KEY AUTOINCREMENT, interface_type_id INT, name TEXT NOT NULL CHECK (NOT name = ''), device_id INT, notes TEXT, FOREIGN KEY(interface_type_id) REFERENCES interface_type(id), FOREIGN KEY(device_id) REFERENCES device(id))");
  $dbh->do("CREATE TABLE connection_type(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK (NOT name = ''))");
  $dbh->do("CREATE TABLE connection(".
    "id INTEGER PRIMARY KEY AUTOINCREMENT, from_interface_id INT, to_interface_id INT, connection_type_id INT, notes TEXT, ".
    "FOREIGN KEY(connection_type_id) REFERENCES connection_type(id), ".
    "FOREIGN KEY(from_interface_id) REFERENCES interface(id), ".
    "FOREIGN KEY(to_interface_id) REFERENCES interface(id))");

  $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'switch')");
  $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'computer')");
  $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'patch panel')");
  $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'wall sockets')");
  $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'KVM switch')");

  $dbh->do("INSERT INTO connection_type (id, name) VALUES (null, 'cable')");
  $dbh->do("INSERT INTO connection_type (id, name) VALUES (null, 'building cabling')");

  $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'Ethernet (copper)')");
  $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'Ethernet (fiber)')");
  $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'Serial console')");
  $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'KVM')");
}

sub print_help() {
    print "Help!\n";
    print "list (room|device|interface|rack|connection)\n";
}

sub print_help_list() {
    print "Help! List!\n";
}

sub print_help_add() {
    print "caman.pl add room <name> [<description> [notes]]\n";
    print "caman.pl add rack <name> <roomid> [<description> [notes]]\n";
    print "caman.pl add device <name> <typeid> <rackid> [<description> [notes]]\n";
    print "caman.pl add interface <name> <typeid> <deviceid> [notes]\n";
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
			$sth = $dbh->prepare("SELECT id, name, description, notes FROM room");
			$table = Text::Table->new("ID", "Name", "Description", "Notes");
		    }
		    case "device" {
			$sth = $dbh->prepare("SELECT device.id, device_type.name, device.name, rack.name, device.description, device.notes FROM device INNER JOIN device_type ON device.device_type_id=device_type.id INNER JOIN rack ON device.rack_id=rack.id ORDER BY rack.name");
			$table = Text::Table->new("ID", "Type", "Name", "Rack", "Description", "Notes");
		    }
		    case "rack" {
			$sth = $dbh->prepare("SELECT rack.id, rack.name, rack.description, room.name, rack.notes FROM rack INNER JOIN room ON rack.room_id=room.id ORDER BY room.name");
			$table = Text::Table->new("ID", "Name", "Description", "Room", "Notes");
		    }
		    case "interface" {
			$sth = $dbh->prepare("SELECT interface.id, interface.name, interface_type.name, device.name, interface.notes FROM interface INNER JOIN interface_type ON interface.interface_type_id=interface_type.id INNER JOIN device ON interface.device_id=device.id ORDER BY device.name ASC, interface.name ASC");
			$table = Text::Table->new("ID", "Name", "Type", "Device", "Notes");
		    }
		    case "connection" {
			$sth = $dbh->prepare("SELECT connection.id, d1.name || '.' || i1.name, d2.name || '.' || i2.name, connection_type.name FROM connection, device as d1, interface as i1, device as d2, interface as i2, connection_type WHERE i1.id=connection.from_interface_id AND i1.device_id=d1.id AND i2.id=connection.to_interface_id AND i2.device_id=d2.id AND connection.connection_type_id=connection_type.id ORDER BY connection_type.name ASC, d1.name ASC");
			$table = Text::Table->new("ID", "From", "To", "Type");
		    }
		    else { print_help_list(); }
		}
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
	}
	case "add" {
	    my $subcommand = shift;
	    if (!$subcommand) {
		print_help_add();
	    } else {
		switch ($subcommand) {
		    # add device <name> [<description> [notes]]
		    case "room" {
			my $name = shift;
			if ($name) {
			    my $description = shift;
			    my $notes = shift;
			    my $query = "INSERT INTO room (name";
			    my $values = "('".$name."'";
			    if ($description) {
				$query = $query.",description";
				$values = $values.",'".$description."'";
			    }
			    if ($notes) {
				$query = $query.",notes";
				$values = $values.",'".$notes."'";
			    }
			    $query = $query.") VALUES ".$values.")";
			    $sth = $dbh->prepare($query);
			} else {
			    print_help_add();
			}
		    }
		    # add device <name> <roomid> [<description> [notes]]
		    case "rack" {
			my $name = shift;
			my $roomid = shift;
			if ($name && $roomid) {
			    my $description = shift;
			    my $notes = shift;
			    my $query = "INSERT INTO rack (name, room_id";
			    my $values = "('".$name."',".$roomid;
			    if ($description) {
				$query = $query.",description";
				$values = $values.",'".$description."'";
			    }
			    if ($notes) {
				$query = $query.",notes";
				$values = $values.",'".$notes."'";
			    }
			    $query = $query.") VALUES ".$values.")";
			    $sth = $dbh->prepare($query);
			} else {
			    print_help_add();
			}
		    }
		    # add device <name> <typeid> <rackid> [<description> [notes]]
		    case "device" {
			my $name = shift;
			my $typeid = shift;
			my $rackid = shift;
			if ($name && $typeid && $rackid) {
			    my $description = shift;
			    my $notes = shift;
			    my $query = "INSERT INTO device (name, device_type_id, rack_id";
			    my $values = "('".$name."',".$typeid.",".$rackid;
			    if ($description) {
				$query = $query.",description";
				$values = $values.",'".$description."'";
			    }
			    if ($notes) {
				$query = $query.",notes";
				$values = $values.",'".$notes."'";
			    }
			    $query = $query.") VALUES ".$values.")";
			    $sth = $dbh->prepare($query);
			} else {
			    print_help_add();
			}
		    }
		    # add interface <name> <typeid> <deviceid> [notes]
		    case "interface" {
			my $name = shift;
			my $typeid = shift;
			my $deviceid = shift;
			if ($name && $typeid && $deviceid) {
			    my $notes = shift;
			    my $query = "INSERT INTO interface (name, interface_type_id, device_id";
			    my $values = "('".$name."',".$typeid.",".$deviceid;
			    if ($notes) {
				$query = $query.",notes";
				$values = $values.",'".$notes."'";
			    }
			    $query = $query.") VALUES ".$values.")";
			    $sth = $dbh->prepare($query);
			} else {
			    print_help_add();
			}
		    }
		}
	    }
	    if ($sth) {
		$sth->execute();
		$sth->finish();
	    }
	}
	else { print_help(); }
    }
} else {
    print_help();
}

$dbh->disconnect();
