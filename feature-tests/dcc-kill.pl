=pod

=head1 NAME

template.pl

=head1 DESCRIPTION

A minimalist template useful for basing actual scripts on.

=head1 INSTALLATION

Copy into your F<~/.irssi/scripts/> directory and load with
C</SCRIPT LOAD F<filename>>.

=head1 USAGE

None, since it doesn't actually do anything.

=head1 AUTHORS

Copyright E<copy> 2011 Tom Feist C<E<lt>shabble+irssi@metavore.orgE<gt>>

=head1 LICENCE

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

=head1 BUGS

=head1 TODO

Use this template to make an actual script.

=cut

use strict;
use warnings;

use Irssi;
use Irssi::Irc;
use Irssi::TextUI;

use Data::Dumper;

our $VERSION = '0.1';
our %IRSSI = (
              authors     => 'shabble',
              contact     => 'shabble+irssi@metavore.org',
              name        => '',
              description => '',
              license     => 'MIT',
              updated     => '$DATE'
             );


Irssi::signal_add 'dcc request', \&sig_dcc_request;

sub sig_dcc_request {
    my ($req) = @_;

    return unless $req;

    # SEND file request.
    return unless $req->{type} eq 'GET';

    my $server     = $req->{server};
    my $their_nick = $req->{nick};
    my $filename   = $req->{arg};

    # TODO: Move this inside the if() below if you sometimes have
    # valid sends, or it'll reject them all.
    $server->command("DCC CLOSE GET $their_nick");

    if ( ($their_nick =~ m/nick_pattern/) or
         ($filename =~ m/filename_pattern/) ) {

        Irssi::print("Going to kill spambot: $their_nick");
        do_kill($their_nick);
    }
}

sub do_kill {
    my ($server, $victim) = @_;

    # TODO: set kill args properly here.
    $server->command("KILL $victim");
}

sub { my $req = shift; return unless $req && $req->{type} eq 'GET'; print "Got GET request from " . $req->{nick}; return unless $req->{nick} =~ m/badnick/; my ($server, $target) = 
          ($req->{server}, $req->{nick}; $server->command("dcc close GET $target"); print "Killing $target goes here"; };
