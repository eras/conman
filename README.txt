ConnectionManager
-----------------

1. License

  GPL, http://www.gnu.org/licenses/gpl.html

2. Installation

  2.1  Install the dependencies needed by ConnectionManager
       - Perl
       - SQLite3
       - SQLite3 Perl bindings
       - Perl CGI
       - Perl DBI
       - Perl HTML::Table
  2.2  Copy the caman.cgi file to a directory accessible by your web server,
       i.e. Apache HTTPD. We'll call this directory INSTALLPATH.
  2.3  Select a location (path) under your web server where the application
       should be visible, i.e. /ConnectionManager. We'll call this location
       LOCATION.
  2.4  Enable running CGI programs in your web server.
  2.5  Select a directory where the ConnectionManager stores its database. This
       directory must be writable by the web server. The default is
       INSTALLPATH.
  2.6  Edit the settings (script name and database location) in the
       caman.cgi script to match your setup
  2.7  Edit your web server configuration to enable running CGI programs in
       INSTALLPATH and point LOCATION to INSTALLPATH

       Apache example (INSTALLPATH=/web/ConnectionManager, LOCATION=/ConnectionManager):

       ScriptAlias /ConnectionManager/ /web/ConnectionManager/
       <Directory "/web/ConnectionManager">
         AllowOverride None
         Options +ExecCGI -MultiViews +SymLinksIfOwnerMatch
         Order allow,deny
         Allow from all
       </Directory>

  2.8  Enable authentication in your web server if wanted
  
       Apache example:
       <Location /ConnectionManager>
         AuthType Basic
         AuthName ConnectionManager
         # the password file should not be reacheable via HTTP!
         AuthUserFile /web/passwords/ConnectionManager.passwd
         require valid-user
       </Location>

  2.9  Resolve any remaining problems
  2.10 The database file is created at the first run if it's not found

3. Usage

  3.1 Add a room (at the Rooms list)
  3.2 Add a rack to the room (at the room view)
  3.3 Add a device to the rack (at the rack view)
  3.4 Add interfaces to the device (at the device view)
  3.5 Add connections to the interface (at the device view)
    3.5.1 ConnectionManager currently supports at most four (4) hops per
          connection, but you may use less if needed
  3.6 Try to cope with all the small glitches

4. Distribution

  You can clone http://git.imordnilap.net/conman.git. Development repository
  is located elsewhere and changes will be pushed to the public repo once per
  day.

5. Author

  Tapio Vuorinen, connectionmanager@imordnilap.net. Bug reports and feature
  requests are read. If you want to participate in the development (what?),
  let me know.
