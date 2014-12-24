package Prancer::Plugin::Database;

use strict;
use warnings FATAL => 'all';

use version;
our $VERSION = '1.01';

use Prancer::Plugin;
use parent qw(Prancer::Plugin Exporter);

use Module::Load ();
use Try::Tiny;
use Carp;

our @EXPORT_OK = qw(database);
our %EXPORT_TAGS = ('all' => [ @EXPORT_OK ]);

# even though this *should* work automatically, it was not
our @CARP_NOT = qw(Prancer Try::Tiny);

sub load {
    my $class = shift;

    # already got an object
    return $class if ref($class);

    # this is a singleton
    my $instance = undef;
    {
        no strict 'refs';
        $instance = \${"${class}::_instance"};
        return $$instance if defined($$instance);
    }

    my $self = bless({}, $class);

    my $config = $self->config->get("database");
    unless (defined($config) && ref($config) && ref($config) eq "HASH") {
        croak "could not initialize database connection: no configuration found";
    }

    my $handles = {};
    for my $key (keys %{$config}) {
        my $subconfig = $config->{$key};

        unless (defined($subconfig) && ref($subconfig) && ref($subconfig) eq "HASH" && $subconfig->{'driver'}) {
            croak "could not initialize database connection '${key}': no database driver configuration";
        }

        my $module = $subconfig->{'driver'};

        # try to load the module and make sure it has required subroutines
        try {
            # load the module
            Module::Load::load($module);

            # make sure it has necessary implementation details
            die "${module} does not implement 'handle'\n" unless ($module->can("handle"));

            # make the connection to the database
            $handles->{$key} = $module->new($subconfig->{'options'}, $key);
        } catch {
            my $error = (defined($_) ? $_ : "unknown");
            croak "could not initialize database connection '${key}': not able to load ${module}: ${error}";
        };
    }
    $self->{'_handles'} = $handles;

    # now export the keyword with a reference to $self
    {
        ## no critic (ProhibitNoStrict ProhibitNoWarnings)
        no strict 'refs';
        no warnings 'redefine';
        *{"${\__PACKAGE__}::database"} = sub {
            my $this = ref($_[0]) && $_[0]->isa(__PACKAGE__) ?
                shift : (defined($_[0]) && $_[0] eq __PACKAGE__) ?
                bless({}, shift) : bless({}, __PACKAGE__);
            return $self->_database(@_);
        };
    }

    $$instance = $self;
    return $self;
}

sub _database {
    my $self = shift;
    my $connection = shift || "default";

    if (!exists($self->{'_handles'}->{$connection})) {
        croak "could not get connection to database: no connection named '${connection}'";
    }

    return $self->{'_handles'}->{$connection}->handle();
}

1;

=head1 NAME

Prancer::Plugin::Database

=head1 SYNOPSIS

This plugin enables connections to a database and exports a keyword to access
those configured connections.

It's important to remember that when running your application in a single-
threaded, single-process application server like, say, L<Twiggy>, all users of
your application will use the same database connection. If you are using
callbacks then this becomes very important and you will want to take care to
avoid crossing transactions or expecting a database connection or transaction
to be in the same state it was before a callback.

To use a database connector, add something like this to your configuration
file:

    database:
        connection-name:
            driver: Prancer::Plugin::Database::Driver::DriverName
            options:
                username: test
                password: test
                database: test
                hostname: localhost
                port: 5432
                autocommit: true
                charset: utf8
                connection_check_threshold: 10

The "connection-name" can be anything you want it to be. This will be used when
requesting a connection from the plugin to determine which connection to return.
If only one connection is configured it may be prudent to call it "default" as
that is the name that Prancer will look for if no connection name is given.
For example:

    use Prancer::Plugin::Database qw(database);

    Prancer::Plugin::Database->load();

    my $dbh = database;  # returns whatever connection is called "default"
    my $dbh = database("foo");  # returns the connection called "foo"

=head1 OPTIONS

=over 4

=item database

B<REQUIRED> The name of the database to connect to.

=item username

The username to use when connecting. If this option is not set then the default
is the user running the application server or the current user.

=item password

The password to use when connecting. If this option is not set then the default
is to connect with no password.

=item hostname

The host name of the database server. If this option is not set then the
default is to connect to localhost.

=item port

The port number on which the database server is listening. If this option is
not set then the default is to connect on the database's default port.

=item autocommit

If set to a true value -- like 1, yes, or true -- then this will enable
autocommit. If set to a false value -- like 0, no, or false -- then this will
disable autocommit. By default, autocommit is enabled.

=item charset

The character set to connect to the database with. If this is set to "utf8"
then the database connection will attempt to make UTF8 data Just Work if
available.

=item connection_check_threshold

This sets the number of seconds that must elapse between calls to get a
database handle before performing a check to ensure that a database connection
still exists and will reconnect if one does not. This handles cases where the
database handle hasn't been used in a while and the underlying connection has
gone away. If this is not set then it will default to 30 seconds.

=back

=head1 CREDIT

This module is derived from L<Dancer::Plugin::Database>. Thank you to David
Precious.

=head1 COPYRIGHT

Copyright 2014 Paul Lockaby. All rights reserved.

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=over

=item

L<Prancer>

=back

=cut
