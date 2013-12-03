#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Switch;
use HTML::Table;
use CGI qw(:standard);

# user editable variables begin
my $dbfile = './cables.db';
my $scriptname = 'conman.cgi';
my $readonlymode = 0;
# user editable variables end

my $MAXHOPS = 4; # changing this requires changes also to html (link1, link2, ... link[MAXHOPS-1])

my $query_interface_id_name = "SELECT interface.id, device.name || '.' || interface.name FROM interface INNER JOIN device ON device.id = interface.device_id ORDER BY device.name ASC, interface.name ASC";
my $query_interface_type_id_name = "select id, name from interface_type";
my $query_device_type_id_name = "select id, name from device_type";
my $query_room_id_name = "select id, name from room";
my $query_rack_id_name = "select id, name from rack";

my $query_list_room = "SELECT id, name, description, notes FROM room ORDER BY name ASC";
my $query_list_rack = "SELECT rack.id, rack.name, rack.description, room.name, rack.notes FROM rack INNER JOIN room ON rack.room_id=room.id ORDER BY rack.name ASC";
my $query_list_device = "SELECT device.id, device.name, device_type.name, rack.name, device.description, device.notes FROM device INNER JOIN device_type ON device.device_type_id=device_type.id INNER JOIN rack ON device.rack_id=rack.id ORDER BY device.name";
my $query_list_interface = "SELECT interface.id, device.name || '.' || interface.name, interface_type.name, interface.notes FROM interface INNER JOIN interface_type ON interface.interface_type_id=interface_type.id INNER JOIN device ON interface.device_id=device.id ORDER BY device.name ASC, interface.name ASC";
my $query_list_connection = "SELECT i1.id, d1.name || '.' || i1.name, d2.name || '.' || i2.name, linklist.seq FROM interface AS i1, interface AS i2, linklist, device AS d1, device AS d2 WHERE linklist.from_interface_id = i1.id AND linklist.interface_id=i2.id AND i1.device_id=d1.id AND i2.device_id=d2.id ORDER BY d1.name, i1.name, linklist.seq";

my $dbh;

sub init_db() {
    if ($readonlymode == 1) {
	return;
    }
    $dbh->do("CREATE TABLE device_type(id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
    $dbh->do("CREATE TABLE room(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK (NOT name = ''), description TEXT, notes TEXT)");
    $dbh->do("CREATE TABLE rack(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK (NOT name = ''), description TEXT, room_id INT, notes TEXT, FOREIGN KEY(room_id) REFERENCES room(id))");
    $dbh->do("CREATE TABLE device(id INTEGER PRIMARY KEY AUTOINCREMENT, device_type_id INT, name TEXT NOT NULL  CHECK (NOT name = ''), description TEXT, rack_id INT, notes TEXT, FOREIGN KEY(rack_id) REFERENCES rack(id), FOREIGN KEY(device_type_id) REFERENCES device_type(id))");
    $dbh->do("CREATE TABLE interface_type(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK (NOT name = ''))");
    $dbh->do("CREATE TABLE interface(id INTEGER PRIMARY KEY AUTOINCREMENT, interface_type_id INT, name TEXT NOT NULL CHECK (NOT name = ''), device_id INT, notes TEXT, FOREIGN KEY(interface_type_id) REFERENCES interface_type(id), FOREIGN KEY(device_id) REFERENCES device(id))");
    
    $dbh->do("CREATE TABLE linklist(".
	     "id INTEGER PRIMARY KEY AUTOINCREMENT, from_interface_id INT, interface_id INT UNIQUE, seq INT NOT NULL, ".
	     "FOREIGN KEY(from_interface_id) REFERENCES interface(id), ".
	     "FOREIGN KEY(interface_id) REFERENCES interface(id), ".
	     "CHECK (NOT from_interface_id = interface_id))");
    
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'switch')");
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'computer')");
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'patch panel')");
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'wall sockets')");
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'KVM switch')");
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'blade chassis')");
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'webcam')");
    $dbh->do("INSERT INTO device_type (id, name) VALUES (null, 'terminal')");
    
    $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'Ethernet (copper)')");
    $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'Ethernet (fiber)')");
    $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'Serial console')");
    $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'KVM')");
    $dbh->do("INSERT INTO interface_type (id, name) VALUES (null, 'misc')");
}

sub print_header() {
    print <<EOF;
Content-Type: text/html; charset=UTF-8

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">
<html>
<head><title>ConnectionManager</title></head>
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

sub print_refresh_javascript($) {
    my ($params) = @_;
    print "<script type=\"text/javascript\">\n".
	"<!--\n".
	"window.location = \"$scriptname?$params\"\n".
	"//-->\n".
	"</script>\n";
}

sub print_footer() {
    print <<EOF;
</body>
</html>
EOF
}

sub get_connection_id_list_for_interface( $ ) {
    my @connlist;
    my ($id) = @_;
    my $connsth;
    $connsth = $dbh->prepare("select interface.id from interface INNER JOIN device ON interface.device_id=device.id WHERE interface.id = (SELECT DISTINCT from_interface_id FROM linklist WHERE interface_id = ? OR from_interface_id = ?)");
    $connsth->execute($id,$id);
    my $row;
    while ($row = $connsth->fetchrow_arrayref()) {
	push(@connlist, $row->[0]);
    }
    $connsth->finish();

    $connsth = $dbh->prepare("select interface.id from linklist INNER JOIN device ON interface.device_id=device.id INNER JOIN interface ON interface.id=linklist.interface_id WHERE linklist.from_interface_id = (SELECT DISTINCT from_interface_id FROM linklist WHERE interface_id = ? OR from_interface_id = ?) ORDER BY seq ASC");
    $connsth->execute($id,$id);
    while ($row = $connsth->fetchrow_arrayref()) {
	push(@connlist, $row->[0]);
    }
    $connsth->finish();
    return @connlist;
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

sub get_from_interface_id_for_interface($) {
    my ($id) = @_;
    # return self if nothing else found
    my $from_interface_id = $id;

    my $ifsth = $dbh->prepare("SELECT from_interface_id FROM linklist WHERE interface_id = ? OR from_interface_id = ?");
    $ifsth->execute($id, $id);
    my $row;
    while ($row = $ifsth->fetchrow_arrayref()) {
	$from_interface_id = $row->[0];
    }
    $ifsth->finish();
    return $from_interface_id;
}

sub select_id_name($$$) {
    my ($query, $selectname, $default) = @_;
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
    if (!$default) {
        $default=$values[0];
    }
    return popup_menu($selectname, \@values, $default, \%labels);
}

sub delete_connection($) {
    my ($id) = @_;
    if ($readonlymode == 0) {
	my $delconnsth = $dbh->prepare("DELETE FROM linklist WHERE from_interface_id = (SELECT DISTINCT from_interface_id FROM linklist WHERE from_interface_id = ? OR interface_id = ?)");
	$delconnsth->execute($id,$id);
	$delconnsth->finish();
    }
}

sub edit_room($) {
    my ($id) = @_;
    
    my ($name, $notes, $description) = (param('name'), param('notes'), param('description'));
    if ($id && $name) {
	my $query = "UPDATE room SET name='$name'";
	if ($notes) {
	    $query = $query.", notes='$notes'";
	} else {
	    $query = $query.", notes=''";
	}
	if ($description) {
	    $query = $query.", description='$description'";
	} else {
	    $query = $query.", description=''";
	}
	$query = $query." WHERE id = $id";
	if ($readonlymode == 0) {
	    my $updateroomsth = $dbh->prepare($query);
	    $updateroomsth->execute();
	    $updateroomsth->finish();
	}
    }

    my $roomsth = $dbh->prepare("SELECT id, name, description, notes FROM room WHERE id = ?");
    $roomsth->execute($id);

    my $row;
    print start_form(-method=>'get', -action=>"$scriptname");
    if ($row = $roomsth->fetchrow_arrayref()) {
	print "<h2>Room: $row->[1]</h2>\n";
        print "Name: ".textfield('name',$row->[1], 40, 80)."<br/>\n";
        print "Description: ".textfield('description',$row->[2], 40, 80)."<br/>\n";
        print "Notes: ".textfield('notes',$row->[3], 40, 80)."<br/>\n";
    }
    $roomsth->finish();
    print "<input type=\"hidden\" name=\"id\" value=\"$id\"/>\n";
    print '<input type="hidden" name="command" value="edit"/><input type="hidden" name="subcommand" value="room"/>'.submit('submit', 'commit changes');
    print end_form();

    print "<h3>Racks</h3>\n";
    my $racktable = new HTML::Table();
    $racktable->addRow("ID", "Name", "Description", "Notes");
    my $racksth = $dbh->prepare("SELECT id, name, description, notes FROM rack WHERE room_id = ? ORDER BY name");
    $racksth->execute($id);
    while ($row = $racksth->fetchrow_arrayref()) {
	my $rackid = $row->[0];
	$row->[1] = "<a href=\"$scriptname?command=edit&subcommand=rack&id=$rackid\">$row->[1]</a>";
	$racktable->addRow(@$row, "<a href=\"$scriptname?command=remove&subcommand=rack&id=$rackid\">delete rack</a>");
    }
    $racksth->finish();
    $racktable->print;
}

sub edit_rack($) {
    my ($id) = @_;
    
    my ($name, $notes, $roomid, $description) = (param('name'), param('notes'), param('roomid'), param('description'));
    if ($name && $roomid) {
	my $query = "UPDATE rack SET room_id=$roomid, name='$name'";
	if ($notes) {
	    $query = $query.", notes='$notes'";
	} else {
	    $query = $query.", notes=''";
	}
	if ($description) {
	    $query = $query.", description='$description'";
	} else {
	    $query = $query.", description=''";
	}
	$query = $query." WHERE id = $id";
	if ($readonlymode == 0) {
	    my $updateracksth = $dbh->prepare($query);
	    $updateracksth->execute();
	    $updateracksth->finish();
	}
    }

    my $racksth = $dbh->prepare("SELECT id, name, room_id, description, notes FROM rack WHERE id = ?");
    $racksth->execute($id);

    my $row;
    print start_form(-method=>'get', -action=>"$scriptname");
    if ($row = $racksth->fetchrow_arrayref()) {
	print "<h2>Rack: $row->[1]</h2>\n";
        print "Name: ".textfield('name',$row->[1], 40, 80)."<br/>\n";
	print "Room: ".select_id_name($query_room_id_name,'roomid',$row->[2])."<br/>\n";
        print "Description: ".textfield('description',$row->[3], 40, 80)."<br/>\n";
        print "Notes: ".textfield('notes',$row->[4], 40, 80)."<br/>\n";
    }    
    $racksth->finish();
    print "<input type=\"hidden\" name=\"id\" value=\"$id\"/>\n";
    print '<input type="hidden" name="command" value="edit"/><input type="hidden" name="subcommand" value="rack"/>'.submit('submit', 'commit changes');
    print end_form();

    print "<h3>Devices</h3>\n";
    my $devtable = new HTML::Table();
    $devtable->addRow("ID", "Name", "Type", "Description", "Notes");
    my $devsth = $dbh->prepare("SELECT device.id, device.name, device_type.name, device.description, device.notes FROM device INNER JOIN device_type ON device.device_type_id=device_type.id WHERE device.rack_id = ? ORDER BY device.name");
    $devsth->execute($id);
    while ($row = $devsth->fetchrow_arrayref()) {
	my $devid = $row->[0];
	$row->[1] = "<a href=\"$scriptname?command=edit&subcommand=device&id=$devid\">$row->[1]</a>";
	$devtable->addRow(@$row, "<a href=\"$scriptname?command=remove&subcommand=device&id=$devid\">delete device</a>");
    }
    $devsth->finish();
    $devtable->print;
}

sub edit_device($) {
    my ($id) = @_;

    my ($name, $notes, $rackid, $devtypeid, $description) = (param('name'), param('notes'), param('rackid'), param('devtypeid'), param('description'));
    if ($name && $rackid && $devtypeid) {
	my $query = "UPDATE device SET rack_id=$rackid, device_type_id=$devtypeid, name='$name'";
	if ($notes) {
	    $query = $query.", notes='$notes'";
	} else {
	    $query = $query.", notes=''";
	}
	if ($description) {
	    $query = $query.", description='$description'";
	} else {
	    $query = $query.", description=''";
	}
	$query = $query." WHERE id = $id";
	if ($readonlymode == 0) {
	    my $updatedevsth = $dbh->prepare($query);
	    $updatedevsth->execute();
	    $updatedevsth->finish();
	}
    }

    my $devsth = $dbh->prepare("SELECT device.id, device_type.name, device.name, rack.name, device.description, device.notes, device.rack_id, device.device_type_id FROM device INNER JOIN device_type ON device.device_type_id=device_type.id INNER JOIN rack ON device.rack_id=rack.id WHERE device.id = ?");
    $devsth->execute($id);

    my $row;
    print start_form(-method=>'get', -action=>"$scriptname");
    if ($row = $devsth->fetchrow_arrayref()) {
	print "<h2>Device: $row->[2]</h2>\n";
        print "Name: ".textfield('name',$row->[2], 40, 80)."<br/>\n";
	print "Type: ".select_id_name($query_device_type_id_name,'devtypeid',$row->[7])."<br/>\n";
	print "Rack: ".select_id_name($query_rack_id_name,'rackid',$row->[6])."<br/>\n";
        print "Description: ".textfield('description',$row->[4], 40, 80)."<br/>\n";
        print "Notes: ".textfield('notes',$row->[5], 40, 80)."<br/>\n";
    }
    $devsth->finish();
    print "<input type=\"hidden\" name=\"id\" value=\"$id\"/>\n";
    print '<input type="hidden" name="command" value="edit"/><input type="hidden" name="subcommand" value="device"/>'.submit('submit', 'commit changes');
    print end_form();

    print "<h3>Interfaces</h3>\n";
    print start_form(-method=>'get', -action=>"$scriptname");
    my $inttable = new HTML::Table();
    $inttable->addRow("ID", "Name", "Type", "Notes", "Connections");
    my $devintsth = $dbh->prepare("SELECT interface.id, interface.name, interface_type.name, interface.notes FROM interface INNER JOIN interface_type ON interface.interface_type_id=interface_type.id WHERE interface.device_id = ? ORDER BY interface.name");
    $devintsth->execute($id);
    while ($row = $devintsth->fetchrow_arrayref()) {
	my @connections;
	my @addhopform;
	@connections = get_connection_list_for_interface($row->[0]);
	if (@connections < $MAXHOPS) {
	    my $seq = @connections;
	    # if there are no connections from the starting point, @collections == 0
	    # if there is one, @collections == 2, hence the following ugly hack
	    if ($seq == 0) {
		$seq = 1;
	    }
	    $inttable->addRow((start_form(-method=>'get', -action=>"$scriptname")));
	    push(@addhopform, (select_id_name($query_interface_id_name,'hopid',0).'<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="hop"/><input type="hidden" name="fromintid" value="'.get_from_interface_id_for_interface($row->[0]).'"/><input type="hidden" name="seq" value="'.$seq.'"/>', submit('submit','add hop')));
	}
	if (@connections > 1) {
	    $inttable->addRow(@$row, @connections, @addhopform, "<a href=\"$scriptname?command=remove&subcommand=connection&id=$row->[0]\">delete connection</a>");
	} else {
	    $inttable->addRow(@$row, @addhopform, "<a href=\"$scriptname?command=remove&subcommand=interface&id=$row->[0]\">delete interface</a>");
	}
	if (@connections < $MAXHOPS) {
	    $inttable->addRow((end_form()));
	}
    }
    $devintsth->finish();
    $inttable->addRow((start_form(-method=>'get', -action=>"$scriptname")));
    my @addconnectionform;
    @addconnectionform = ('', '', '', '', select_id_name($query_interface_id_name,'fromintid',0), select_id_name($query_interface_id_name,'link1',0), select_id_name($query_interface_id_name,'link2',0), select_id_name($query_interface_id_name,'link3',0).hidden('fromintid',$row->[0]).'<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="connection"/>', submit('submit','add conn'));
    $inttable->addRow(@addconnectionform);
    $inttable->addRow((end_form()));
    $inttable->print;

    print "<h4>Add a new interface</h4>\n";
    print start_form(-method=>'get', -action=>"$scriptname");
    $inttable = new HTML::Table();
    $inttable->addRow(textfield('name','name',10,20), select_id_name($query_interface_type_id_name,'typeid',0), textfield('notes','', 20,40), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="interface"/>'.hidden('deviceid',"$id").submit('submit', 'add'));
    $inttable->print;
    print end_form();
}

sub device_id_for_interface($) {
    my ($id) = @_;

    my $devid;
    my $row;
    my $devsth = $dbh->prepare("SELECT device_id FROM interface WHERE id = ?");
    $devsth->execute($id);
    while ($row = $devsth->fetchrow_arrayref()) {
	$devid = $row->[0];
    }
    $devsth->finish();
    return $devid;
}

##################################################################3
# sub-routines end, main begins
##################################################################3

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
		    $sth = $dbh->prepare($query_list_room);
		    $table->addRow("ID", "Name", "Description", "Notes");
		    @addNewItemRow = ("", textfield('name','name',20,80), textfield('description','description', 40, 80), textfield('notes', 'notes', 40, 80), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="room"/>'.submit('submit', 'add'));
		}
		case "rack" {
		    $sth = $dbh->prepare($query_list_rack);
		    $table->addRow("ID", "Name", "Description", "Room", "Notes");
		    @addNewItemRow = ("", textfield('name','name',20,80), textfield('description','description', 40, 80), select_id_name($query_room_id_name,'roomid',0), textfield('notes', 'notes', 40, 80), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="rack"/>'.submit('submit', 'add'));
		}
		case "device" {
		    $sth = $dbh->prepare($query_list_device);
		    $table->addRow("ID", "Name", "Type", "Rack", "Description", "Notes");
		    @addNewItemRow = ("", textfield('name','name',20,80), select_id_name($query_device_type_id_name,'devtypeid',0), select_id_name($query_rack_id_name,'rackid',0), textfield('description','description', 40, 80), textfield('notes', 'notes', 40, 80), '<input type="hidden" name="command" value="add"/><input type="hidden" name="subcommand" value="device"/>'.submit('submit', 'add'));
		}
		case "interface" {
		    $sth = $dbh->prepare($query_list_interface);
		    $table->addRow("ID", "Name", "Type", "Notes");
		}
		case "connection" {
		    $sth = $dbh->prepare($query_list_connection);
		    $table->addRow("Start if ID", "From", "Hops", "Seq");
		}
	    }
	    if ($sth) {
		$sth->execute();
		my $row;
		while ($row = $sth->fetchrow_arrayref()) {
		    my $id=$row->[0];
		    $row->[1] = "<a href=\"$scriptname?command=edit&subcommand=$subcommand&id=$id\">$row->[1]</a>";
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
			if ($readonlymode == 0) {
			    $sth = $dbh->prepare($query);
			    $sth->execute();
			    $sth->finish();
			}
		    }
		    print_refresh_javascript("command=list&subcommand=room");
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
			if ($readonlymode == 0) {
			    $sth = $dbh->prepare($query);
			    $sth->execute();
			    $sth->finish();
			}
		    }
		    print_refresh_javascript("command=list&subcommand=rack");
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
			if ($readonlymode == 0) {
			    $sth = $dbh->prepare($query);
			    $sth->execute();
			    $sth->finish();
			}
		    }
		    print_refresh_javascript("command=list&subcommand=device");
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
			if ($readonlymode == 0) {
			    $sth = $dbh->prepare($query);
			    $sth->execute();
			    $sth->finish();
			}
		    }
		    print_refresh_javascript("command=edit&subcommand=device&id=$deviceid");
		}
		# add connection <fromintid> <tointid> <conntypeid> [notes]
		case "connection" {
		    my $fromintid = param('fromintid');
		    if ($fromintid) {
			for (my $i = 1;$i < $MAXHOPS;$i++) {
			    my $link = param("link$i");
			    if ($link) {
				my $query = "INSERT INTO linklist (from_interface_id, interface_id, seq";
				my $values = "('".$fromintid."',".$link.",".$i;
				$query = $query.") VALUES ".$values.")";
				if ($readonlymode == 0) {
				    $sth = $dbh->prepare($query);
				    $sth->execute();
				    $sth->finish();
				}
			    }
			}
		    }
		    print_refresh_javascript("command=edit&subcommand=device&id=".device_id_for_interface($fromintid));
		}
		case "hop" {
		    my $fromintid = param('fromintid');
		    my $seq = param('seq');
		    my $hopid = param('hopid');

		    my $query = "INSERT INTO linklist (from_interface_id, interface_id, seq) VALUES (?, ?, ?)";
		    if ($readonlymode == 0) {
			$sth = $dbh->prepare($query);
			$sth->execute($fromintid, $hopid, $seq);
			$sth->finish();
		    }
		    print_refresh_javascript("command=edit&subcommand=device&id=".device_id_for_interface($fromintid));
		}
	    }
	}
	case "remove" {
	    my $id = param('id');
	    if ($subcommand && $id && ($readonlymode == 0)) {
		switch ($subcommand) {
		    case "room" {
			$sth = $dbh->prepare("DELETE FROM room where id = ?");
			$sth->execute($id);
			$sth->finish();
			print_refresh_javascript("command=list&subcommand=room");
		    }
		    case "rack" {
			$sth = $dbh->prepare("DELETE FROM rack where id = ?");
			$sth->execute($id);
			$sth->finish();
			print_refresh_javascript("command=list&subcommand=rack");
		    }
		    case "device" {
			$sth = $dbh->prepare("DELETE FROM device where id = ?");
			$sth->execute($id);
			$sth->finish();
			print_refresh_javascript("command=list&subcommand=device");
		    }
		    case "interface" {
			my $devid = device_id_for_interface($id);
			$sth = $dbh->prepare("DELETE FROM interface where id = ?");
			$sth->execute($id);
			$sth->finish();
			print_refresh_javascript("command=edit&subcommand=device&id=$devid");
		    }
		    case "connection" {
			delete_connection($id);
			print "Click 'Back' and 'Refresh'<br/>\n";
		    }
		}
	    }
	}
	case "edit" {
	    my $id = param('id');
	    if ($subcommand && $id) {
		switch ($subcommand) {
		    case "room" {
			edit_room($id);
		    }
		    case "rack" {
			edit_rack($id);
		    }
		    case "device" {
			edit_device($id);
		    }
		    case "interface" {
			edit_device(device_id_for_interface($id));
		    }
		    case "connection" {
			edit_device(device_id_for_interface($id));
		    }
		}
	    }
	}
    }
}

$dbh->disconnect();

print_footer();
