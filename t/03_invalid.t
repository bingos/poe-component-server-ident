use Test::More tests => 4;

use Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);
use_ok( 'POE::Component::Server::Ident' );

my $identd = POE::Component::Server::Ident->spawn ( Alias => 'Ident-Server', BindAddr => '127.0.0.1', BindPort => 0, Multiple => 1 );

isa_ok( $identd, 'POE::Component::Server::Ident' );

POE::Session->create
  ( inline_states =>
      { _start => \&client_start,
	_stop  => \&client_stop,
	_sock_up => \&_sock_up,
	_sock_failed => \&_sock_failed,
	_parseline => \&_parseline,
	identd_request => \&identd_request,
      },
    heap => { Port1 => 12345, Port2 => 123, UserID => 'bingos', Identd => $identd },
  );

POE::Kernel->run();
exit;

sub client_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  my ($remoteport,undef) = unpack_sockaddr_in( $heap->{Identd}->getsockname() );

  $kernel->call ( 'Ident-Server' => 'register' );

  $heap->{'SocketFactory'} = POE::Wheel::SocketFactory->new (
				RemoteAddress => '127.0.0.1',
				RemotePort => $remoteport,
				SuccessEvent => '_sock_up',
                                FailureEvent => '_sock_failed',
				BindAddress => '127.0.0.1'
                             );
  undef;
}

sub client_stop {
  pass("Client stopped");
  undef;
}

sub _sock_up {
  my ($kernel,$heap,$socket) = @_[KERNEL,HEAP,ARG0];

  delete $heap->{'SocketFactory'};

  $heap->{'socket'} = new POE::Wheel::ReadWrite
  (
        Handle => $socket,
        Driver => POE::Driver::SysRW->new(),
        Filter => POE::Filter::Line->new( Literal => "\x0D\x0A" ),
        InputEvent => '_parseline',
        ErrorEvent => '_sock_down',
   );

  $heap->{'socket'}->put("Garbage");
  undef;
}

sub _sock_failed {
  $_[KERNEL]->call ( 'Ident-Server' => 'shutdown' );
  undef;
}

sub _sock_down {
  my ($kernel, $heap) = @_[KERNEL, HEAP];
  delete $heap->{'socket'};
  undef;
}

sub _parseline {
  my ($kernel,$heap,$input) = @_[KERNEL,HEAP,ARG0];
  ok( $input =~ /INVALID-PORT/, "Got the reply" );
  #$kernel->post ( 'Ident-Server' => 'unregister' );
  $kernel->post ( 'Ident-Server' => 'shutdown' );
  delete $heap->{'socket'};
  undef;
}

sub identd_request {
  my ($kernel,$heap,$sender,$peeraddr,$first,$second) = @_[KERNEL,HEAP,SENDER,ARG0,ARG1,ARG2];
  undef;
}
