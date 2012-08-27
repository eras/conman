#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Switch;
use HTML::Table;
use CGI qw(:standard);

# TODO
# - removing links from device view

# user editable variables begin
my $dbfile = './cables.db';
my $scriptname = 'caman.cgi';
# user editable variables end

my $query_interface_id_name = "SELECT interface.id, device.name || '.' || interface.name FROM interface INNER JOIN device ON device.id = interface.device_id ORDER BY device.name ASC, interface.name ASC";
my $query_interface_type_id_name = "select id, name from interface_type";
my $query_device_type_id_name = "select id, name from device_type";
my $query_room_id_name = "select id, name from room";
my $query_rack_id_name = "select id, name from rack";

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

  $dbh->do("CREATE TABLE linklist(".
    "id INTEGER PRIMARY KEY AUTOINCREMENT, from_interface_id INT, interface_id INT, seq INT NOT NULL, ".
    "FOREIGN KEY(from_interface_id) REFERENCES interface(id), ".
    "FOREIGN KEY(interface_id) REFERENCES interface(id))");

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
    print_help_list();
    print_help_add();
}

sub print_help_list() {
    print "caman.pl list (room|device|interface|rack|connection)\n";
}

sub print_help_add() {
    print "caman.pl add room <name> [<description> [notes]]\n";
    print "caman.pl add rack <name> <roomid> [<description> [notes]]\n";
    print "caman.pl add device <name> <typeid> <rackid> [<description> [notes]]\n";
    print "caman.pl add interface <name> <typeid> <deviceid> [notes]\n";
    print "caman.pl add connection <fromintid> <tointid> <conntypeid> [notes]\n";
}

sub print_header() {
    print <<EOF;
Content-Type: text/html; charset=UTF-8

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">
<html>
<head><title>Modeemi CableManager</title></head>
<body>
EOF
}

sub print_navigation() {
    print "<center>\n";
    print "<table>\n";
    print "  <tr>\n";
    print "    <td><a href=\"".$scriptname."?command=list&subcommand=room\">Rooms</a></td>\n";
    print "    <td><a href=\"".$scriptname."?command=list&subcommand=rack\">Racks</a></td>\n";
    print "    <td><a href=\"".$scriptname."?command=list&subcommand=device\">Devices</a></td>\n";
    print "    <td><a href=\"".$scriptname."?command=list&subcommand=interface\">Interfaces</a></td>\n";
    print "    <td><a href=\"".$scriptname."?command=list&subcommand=connection\">Connections</a></td>\n";
    print "  </tr>\n";
    print "</table>\n";
    print "</center>\n";
}

sub print_footer() {
    print <<EOF;
</body>
</html>
EOF
}

sub get_connection_list_for_interface($) {
    my @connlist;
    my ($id) = @_;
    my $connsth;
    $connsth = $dbh->prepare("select device.name || '.' || interface.name from interface INNER JOIN device ON interface.device_id=device.id WHERE interface.id = (SELECT DISTINCT from_interface_id FROM linklist WHERE interface_id = ? OR from_interface_id = ?)");
    $connsth->execute($id,$id);
    my $row;
    while ($row = $connsth->fetchrow_arrayref()) {
	push(@connlist, $row->[0]);
    }
    $connsth->finish();

    $connsth = $dbh->prepare("select device.name || '.' || interface.name from linklist INNER JOIN device ON interface.device_id=device.id INNER JOIN interface ON interface.id=linklist.interface_id WHERE linklist.from_interface_id = (SELECT DISTINCT from_interface_id FROM linklist WHERE interface_id = ? OR from_interface_id = ?) ORDER BY seq ASC");
    $connsth->execute($id,$id);
    while ($row = $connsth->fetchrow_arrayref()) {
	push(@connlist, $row->[0]);
    }
    $connsth->finish();
    return @connlist;
}

sub select_id_name($$) {
    my ($query, $selectname) = @_;
    my $tointidsth = $dbh->prepare($query);
    $tointidsth->execute();
    my $row;
    my %labels;
    my @values;
    push(@values, '');
    while ($row = $tointidsth->fetchrow_arrayref()) {
	push(@values, $row->[0]);
	$labels{$row->[0]} = $row->[1];
    }
    $tointidsth->finish();
    return popup_menu($selectname, \@values, $values[0], \%labels);
}

sub edit_device($) {
    my ($id) = @_;
    my $devsth = $dbh->prepare("SELECT device.id, device_type.name, device.name, rack.name, device.description, device.notes FROM device INNER JOIN device_type ON device.device_type_id=device_type.id INNER JOIN rack ON device.rack_id=rack.id WHERE device.id = ?");
    $devsth->execute($id);

    my $row;
    while ($row = $devsth->fetchrow_arrayref()) {
	print "<h2>$row->[2]</h2>\n";
	print "Type: $row->[1]<br/>\n";
	print "Rack: $row->[3]<br/>\n";
	print "Description: $row->[4]<br/>\n";
	print "Notes: $row->[5]<br/>\n";
    }    
    $devsth->finish();

    print "<h3>Interfaces</h3>\n";
    print start_form(-method=>'get', -action=>"$scriptname");
    my $inttable = new HTML::Table();
    $inttable->addRow("ID", "Name", "Type", "Notes", "Connections");
    my $devintsth = $dbh->prepare("SELECT interface.id, interface.name, interface_type.name, interface.notes FROM interface INNER JOIN interface_type ON interface.interface_type_id=interface_type.id WHERE interface.device_id = ? ORDER BY interface.name");
    $devintsth->execute($id);
    while ($row = $devintsth->fetchrow_arrayref()) {
	my @connections;
	@connections = get_connection_list_for_interface($row->[0]);
	if (@connections > 1) {
	    $inttable->addRow(@$row, @connections, "<a href=\"$scriptname?command=remove&subcommand=connection&id=$row->[0]\">delete connection</a>");
	} else {
	    $inttable->addRow(@$row, "<a href=\"$scriptname?command=remove&subcommand=interface&id=$row->[0]\">delete interface</a>");
	}
    }
    $devintsth->finish();
    $inttable->addRow((start_form(-method=>'get', -action=>"$scriptname")));
    my @addconnectionform;
    @addconnectionform = ('', '', '', '', select_id_name($query_interface_id_name,'fromintid'), select_id_name($query_interface_id_name,'link1'), select_id_name($query_interface_id_name,'link2'), select_id_name($query_interface_id_name,'link3').hidden('fromintid',$row->[0]).'<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="connection"/>', submit('submit','add conn'));
    $inttable->addRow(@addconnectionform);
    $inttable->addRow((end_form()));
    $inttable->print;

    print "<h4>Add a new interface</h4>\n";
    print start_form(-method=>'get', -action=>"$scriptname");
    $inttable = new HTML::Table();
    $inttable->addRow(textfield('name','name',10,20), select_id_name($query_interface_type_id_name,'typeid'), textfield('notes','', 20,40), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="interface"/>'.hidden('deviceid',"$id").submit('submit', 'add'));
    $inttable->print;
    print end_form();
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

print_header();
print_navigation();

my $sth;
my $command = param('command');
my $subcommand = param('subcommand');
if ($command && $subcommand) {
    switch ($command) {
	case "list" {
	    my $table = new HTML::Table();
	    my @addNewItemRow;
	    switch ($subcommand) {
		case "room" {
		    $sth = $dbh->prepare("SELECT id, name, description, notes FROM room");
		    $table->addRow("ID", "Name", "Description", "Notes");
		    @addNewItemRow = ("", textfield('name','name',20,80), textfield('description','description', 40, 80), textfield('notes', 'notes', 40, 80), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="room"/>'.submit('submit', 'add'));
		}
		case "rack" {
		    $sth = $dbh->prepare("SELECT rack.id, rack.name, rack.description, room.name, rack.notes FROM rack INNER JOIN room ON rack.room_id=room.id ORDER BY room.name");
		    $table->addRow("ID", "Name", "Description", "Room", "Notes");
		    @addNewItemRow = ("", textfield('name','name',20,80), textfield('description','description', 40, 80), select_id_name($query_room_id_name,'roomid'), textfield('notes', 'notes', 40, 80), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="rack"/>'.submit('submit', 'add'));
		}
		case "device" {
		    $sth = $dbh->prepare("SELECT device.id, device_type.name, device.name, rack.name, device.description, device.notes FROM device INNER JOIN device_type ON device.device_type_id=device_type.id INNER JOIN rack ON device.rack_id=rack.id ORDER BY rack.name");
		    $table->addRow("ID", "Type", "Name", "Rack", "Description", "Notes");
		    @addNewItemRow = ("", select_id_name($query_device_type_id_name,'devtypeid'), textfield('name','name',20,80), select_id_name($query_rack_id_name,'rackid'), textfield('description','description', 40, 80), textfield('notes', 'notes', 40, 80), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="device"/>'.submit('submit', 'add'));
		}
		case "interface" {
		    $sth = $dbh->prepare("SELECT interface.id, device.name || '.' || interface.name, interface_type.name, interface.notes FROM interface INNER JOIN interface_type ON interface.interface_type_id=interface_type.id INNER JOIN device ON interface.device_id=device.id ORDER BY device.name ASC, interface.name ASC");
		    $table->addRow("ID", "Name", "Type", "Notes");
		}
		case "connection" {
		    print "<h2>TBD, maybe</h2>\n";
		    $sth = $dbh->prepare("SELECT connection.id, d1.name || '.' || i1.name, d2.name || '.' || i2.name, connection_type.name FROM connection, device as d1, interface as i1, device as d2, interface as i2, connection_type WHERE i1.id=connection.from_interface_id AND i1.device_id=d1.id AND i2.id=connection.to_interface_id AND i2.device_id=d2.id AND connection.connection_type_id=connection_type.id ORDER BY connection_type.name ASC, d1.name ASC");
		    $table->addRow("From", "Hops");
		}
	    }
	    if ($sth) {
		$sth->execute();
		my $row;
		while ($row = $sth->fetchrow_arrayref()) {
		    my $id=$row->[0];
		    $row->[0] = "<a href=\"$scriptname?command=edit&subcommand=$subcommand&id=$id\">$id</a>";
		    $table->addRow((@$row, "<a href=\"$scriptname?command=remove&subcommand=$subcommand&id=$id\">delete</a>"));
		}
		print start_form(-method=>'get', -action=>"$scriptname");
		$table->setRowHead(1);
		if (@addNewItemRow) {
		    $table->addRow(@addNewItemRow);
		}
		$table->print;
		print end_form();
		$sth->finish();
	    }
	}
	case "add" {
	    switch ($subcommand) {
		# add room <name> [<description> [notes]]
		case "room" {
		    my $name = param('name');
		    if ($name) {
			my $description = param('description');
			my $notes = param('notes');
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
			$sth->execute();
			$sth->finish();
		    }
		}
		# add rack <name> <roomid> [<description> [notes]]
		case "rack" {
		    my $name = param('name');
		    my $roomid = param('roomid');
		    if ($name && $roomid) {
			my $description = param('description');
			my $notes = param('notes');
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
			$sth->execute();
			$sth->finish();
		    }
		}
		# add device <name> <devtypeid> <rackid> [<description> [notes]]
		case "device" {
		    my $name = param('name');
		    my $typeid = param('devtypeid');
		    my $rackid = param('rackid');
		    if ($name && $typeid && $rackid) {
			my $description = param('description');
			my $notes = param('notes');
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
			$sth->execute();
			$sth->finish();
		    }
		}
		# add interface <name> <typeid> <deviceid> [notes]
		case "interface" {
		    my $name = param('name');
		    my $typeid = param('typeid');
		    my $deviceid = param('deviceid');
		    if ($name && $typeid && $deviceid) {
			my $notes = param('notes');
			my $query = "INSERT INTO interface (name, interface_type_id, device_id";
			my $values = "('".$name."',".$typeid.",".$deviceid;
			if ($notes) {
			    $query = $query.",notes";
			    $values = $values.",'".$notes."'";
			}
			$query = $query.") VALUES ".$values.")";
			$sth = $dbh->prepare($query);
			$sth->execute();
			$sth->finish();
		    }
		}
		# add connection <fromintid> <tointid> <conntypeid> [notes]
		case "connection" {
		    my $fromintid = param('fromintid');
		    if ($fromintid) {
			for (my $i = 1;$i < 4;$i++) {
			    my $link = param("link$i");
			    if ($link) {
				my $query = "INSERT INTO linklist (from_interface_id, interface_id, seq";
				my $values = "('".$fromintid."',".$link.",".$i;
				$query = $query.") VALUES ".$values.")";
				$sth = $dbh->prepare($query);
				$sth->execute();
				$sth->finish();
			    }
			}
		    }
		}
	    }
	}
	case "remove" {
	    my $id = param('id');
	    if ($subcommand && $id) {
		if ($subcommand eq "connection") {
		    $sth = $dbh->prepare("DELETE FROM linklist WHERE from_interface_id = (SELECT DISTINCT from_interface_id FROM linklist WHERE from_interface_id = ? OR interface_id = ?)");
		    $sth->execute($id,$id);
		    $sth->finish();
		} else {
		    $sth = $dbh->prepare("DELETE FROM $subcommand where id = ?");
		    $sth->execute($id);
		    $sth->finish();
		}
	    }
	}
	case "edit" {
	    my $id = param('id');
	    if ($subcommand && $id) {
		switch ($subcommand) {
		    case "device" {
			edit_device($id);
		    }
		}
	    }
	}
    }
}

$dbh->disconnect();

print_footer();
