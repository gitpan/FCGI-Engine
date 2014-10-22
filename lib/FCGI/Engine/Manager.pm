package FCGI::Engine::Manager;
use Moose;

use FCGI::Engine::Types;
use FCGI::Engine::Manager::Server;

use Config::Any;

our $VERSION   = '0.02';
our $AUTHORITY = 'cpan:STEVAN';

with 'MooseX::Getopt';

has 'conf' => (
    is       => 'ro',
    isa      => 'Path::Class::File',
    coerce   => 1,
    required => 1,
);

has '_config' => (
    is       => 'ro',
    isa      => 'FCGI::Engine::Manager::Config',
    lazy     => 1,
    default  => sub {
        my $self   = shift;
        my $file   = $self->conf->stringify;
        my $config = Config::Any->load_files({ 
            files   => [ $file ],
            use_ext => 1
        })->[0]->{$file};
        #use Data::Dumper; 
        #warn Dumper $config;
        return $config;
    }
);

has '_servers' => (
    reader    => 'servers',
    isa       => 'ArrayRef[FCGI::Engine::Manager::Server]',
    lazy      => 1,
    default   => sub {
        my $self = shift;
        return [ 
            map { 
                $_->{server_class} ||= "FCGI::Engine::Manager::Server";
                Class::MOP::load_class($_->{server_class});
                $_->{server_class}->new(%$_);
            } @{$self->_config} 
        ];
    },
);

sub log { shift; print @_, "\n" }

sub start {
    my $self = shift;
    
    local $| = 1;
    
    $self->log("Starting up the FCGI servers ...");

    foreach my $server (@{$self->servers}) {
    
        my @cli = $server->construct_command_line();
        $self->log("Running @cli");
    
        unless (system(@cli) == 0) {
            $self->log("Could not execute command (@cli) exited with status $?");
            $self->log("... stoping FCGI servers");
            $self->stop;
            return;
        }
    
        my $count = 1;
        until (-e $server->pidfile) {
            $self->log("pidfile (" . $server->pidfile . ") does not exist yet ... (trying $count times)");
            sleep 2;
            $count++;
        }
        
        my $pid = $server->pid_obj;

        while (!$pid->is_running) {
            $self->log("pid (" . $pid->pid . ") with pid_file (" . $server->pidfile . ") is not running yet, sleeping ...");
            sleep 2;
        }

        $self->log("Pid " . $pid->pid . " is running");
    
    }

    $self->log("... FCGI servers have been started");
}

sub status {
    # FIXME:
    # there must be a better way to do this, 
    # and even if there isn't we should come
    # up with a better way to display them
    # (oh yeah and filter out things not related
    # to us as well)
    # - SL
    join "\n" => map { chomp; s/\s+$//; $_ } `ps auxwww | grep fcgi`;    
}

sub stop {
    my $self = shift;
    
    local $| = 1;    
        
    $self->log("Killing the FCGI servers ...");

    foreach my $server (@{$self->servers}) {
    
        if (-f $server->pidfile) {
            
            my $pid = $server->pid_obj;
            
            $self->log("Killing PID " . $pid->pid . " from $$ ");
            kill TERM => $pid->pid;
            
            while ($pid->is_running) {
                $self->log("pid (" . $server->pidfile . ") is still running, sleeping ...");
                sleep 1;
            }                       
        }
    
        if (-e $server->socket) {
            unlink($server->socket);
        }
    
    }    

    $self->log("... FCGI servers have been killed");
}

1;

__END__


=pod

=head1 NAME

FCGI::Engine::Manager - Manage multiple FCGI::Engine instances

=head1 SYNOPSIS

  #!/usr/bin/perl

  my $m = FCGI::Engine::Manager->new(
      conf => 'conf/my_app_conf.yml'
  );
  
  $m->start  if $ARGV[0] eq 'start';
  $m->status if $ARGV[0] eq 'status';
  $m->stop   if $ARGV[0] eq 'stop';    

  # on the command line
  
  perl all_my_fcgi_backends.pl start
  perl all_my_fcgi_backends.pl stop
  # etc ...  

=head1 DESCRIPTION

This module handles multiple L<FCGI::Engine> instances for you, it can 
start, stop and provide basic status info. It is configurable using 
L<Config::Any>, but only really the YAML format has been tested. 

This module is still in it's early stages, many things may change.

=head2 Use with Catalyst

Since L<FCGI::Engine> is pretty much compatible with 
L<Catalyst::Engine::FastCGI>, this module can also be used to manage 
your L<Catalyst::Engine::FastCGI> based apps as well as your 
L<FCGI::Engine> based apps.

=head1 EXAMPLE CONFIGURATION

Here is an example configuration in YAML, it should be noted that 
the options for each server are basically the constructor params to 
L<FCGI::Engine::Manager::Server> and are passed verbatim to it. 
This means that if you subclass L<FCGI::Engine::Manager::Server> 
and set the C<server_class:> option appropriately, it should pass 
any new options you added to your subclass automatically.

  ---
  - name:            "foo.server"
    server_class:    "FCGI::Engine::Manager::Server"
    scriptname:      "t/scripts/foo.pl"
    nproc:            1
    pidfile:         "/tmp/foo.pid"
    socket:          "/tmp/foo.socket" 
    additional_args: [ "-I", "lib/" ]
  - name:       "bar.server"
    scriptname: "t/scripts/bar.pl"
    nproc:       1
    pidfile:    "/tmp/bar.pid"
    socket:     "/tmp/bar.socket"

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2007-2008 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut




