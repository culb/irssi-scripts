# Search and select windows similar to ido-mode for emacs
#
# INSTALL:
#
# This script requires that you have first installed and loaded 'uberprompt.pl'
# Uberprompt can be downloaded from:
#
# http://github.com/shabble/irssi-scripts/raw/master/prompt_info/uberprompt.pl
#
# and follow the instructions at the top of that file for installation.
#
# USAGE:
#
# * Setup: /bind ^G /ido_switch_start
#
# * Then type ctrl-G and type what you're searching for
#
# Based in part on window_switcher.pl script Copyright 2007 Wouter Coekaerts
# <coekie@irssi.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

use strict;
use Irssi;
use Irssi::TextUI;
use Data::Dumper;

use vars qw($VERSION %IRSSI);
$VERSION = '2.0';
%IRSSI =
  (
   authors     => 'Tom Feist, Wouter Coekaerts',
   contact     => 'shabble+irssi@metavore.org, shabble@#irssi/freenode',
   name        => 'ido_switcher',
   description => 'Select window(-items) using ido-mode like search interface',
   license     => 'GPLv2 or later',
   url         => 'http://github.com/shabble/irssi-scripts/tree/master/history-search/',
   changed     => '24/7/2010'
  );


# TODO:
# C-g - cancel
# C-spc - narrow
# flex matching (on by default, but optional)
# server/network narrowing
# colourised output (via uberprompt)
# C-r / C-s rotate matches
# toggle queries/channels
# remove inputline content, restore it afterwards.
# tab - display all possibilities in window (clean up afterwards)
# sort by recent activity/recently used windows (separate commands?)

my $input_copy     = '';
my $input_pos_copy = 0;

my $ido_switch_active = 0;

my @window_cache   = ();
my @search_matches = ();

my $match_index = 0;
my $search_str  = '';
my $active_only = 0;

my $need_clear = 0;

my $sort_ordering = "start-asc";

# /set configurable settings
my $ido_show_count;
my $ido_use_flex;

my $DEBUG_ENABLED = 0;
sub DEBUG () { $DEBUG_ENABLED }

sub MODE_A () { 0 } # all
sub MODE_Q () { 1 } # queries
sub MODE_C () { 2 } # channels
sub MODE_S () { 3 } # select server
sub MODE_W () { 4 } # select window

# check we have uberprompt loaded.

sub _print {
    my $win = Irssi::active_win;
    my $str = join('', @_);
    $need_clear = 1;
    $win->print($str, Irssi::MSGLEVEL_NEVER);
}

sub _debug_print {
    return unless DEBUG;
    my $win = Irssi::active_win;
    my $str = join('', @_);
    $win->print($str, Irssi::MSGLEVEL_CLIENTCRAP);
}

sub _print_clear {
    return unless $need_clear;
    my $win = Irssi::active_win();
    $win->command('/scrollback levelclear -level NEVER');
}

sub print_all_matches {
    my $msg = join(", ", map { $_->{name} } @search_matches);
    # $msg =~ s/(.{80}.*?,)/$1\n/g;
    # my @lines = split "\n", $msg;
    # foreach my $line (@lines) {
    #     _print($line);
    # }
    _print($msg);
}

sub script_is_loaded {
    my $name = shift;
    _debug_print "Checking if $name is loaded";
    no strict 'refs';
    my $retval = defined %{ "Irssi::Script::${name}::" };
    use strict 'refs';

    return $retval;
}

unless (script_is_loaded('uberprompt')) {

    _print "This script requires 'uberprompt.pl' in order to work. "
     . "Attempting to load it now...";

    Irssi::signal_add('script error', 'load_uberprompt_failed');
    Irssi::command("script load uberprompt.pl");

    unless(script_is_loaded('uberprompt')) {
        load_uberprompt_failed("File does not exist");
    }
    ido_switch_init();
}

sub load_uberprompt_failed {
    Irssi::signal_remove('script error', 'load_uberprompt_failed');
    _print "Script could not be loaded. Script cannot continue. "
      . "Check you have uberprompt.pl installed in your path and "
        .  "try again.";
    die "Script Load Failed: " . join(" ", @_);
}

sub ido_switch_init {
    Irssi::settings_add_bool('ido_switch', 'ido_switch_debug', 0);
    Irssi::settings_add_bool('ido_switch', 'ido_use_flex',     1);
    Irssi::settings_add_int ('ido_switch', 'ido_show_count',   5);

    Irssi::command_bind('ido_switch_start', \&ido_switch_start);

    Irssi::signal_add      ('setup changed'   => \&setup_changed);
    Irssi::signal_add_first('gui key pressed' => \&handle_keypress);

    setup_changed();
}

sub setup_changed {
    $DEBUG_ENABLED  = Irssi::settings_get_bool('ido_switch_debug');
    $ido_show_count = Irssi::settings_get_int ('ido_show_count');
    $ido_use_flex   = Irssi::settings_get_bool('ido_use_flex');
}


sub ido_switch_start {
    # store copy of input line to restore later.
    $input_copy     = Irssi::parse_special('$L');
    $input_pos_copy = Irssi::gui_input_get_pos();

    Irssi::gui_input_set('');

    # set startup flags
    $ido_switch_active = 1;
    $search_str        = '';
    $match_index       = 0;

    # refresh in case we toggled it last time.
    $ido_use_flex   = Irssi::settings_get_bool('ido_use_flex');
    $active_only    = 0;

    _debug_print "Win cache: " . join(", ", map { $_->{name} } @window_cache);

    _update_cache();

    update_matches();
    update_prompt();
}

sub _update_cache {
    @window_cache = get_all_windows();
}

sub get_all_windows {
    my @ret;

    foreach my $win (Irssi::windows()) {
        my @items = $win->items();

        if ($win->{name} ne '') {
            _debug_print "Adding window: " . $win->{name};
            push @ret, {
                        name   => $win->{name},
                        type   => 'WINDOW',
                        num    => $win->{refnum},
                        server => $win->{active_server},
                        active => $win->{data_level} > 0,
                        b_pos  => -1,
                        e_pos  => -1,
                       };
        }

        if (scalar @items) {
            foreach my $item (@items) {
                _debug_print "Adding windowitem: " . $item->{visible_name};

                push @ret, {
                            name     => $item->{visible_name},
                            type     => $item->{type},
                            server   => $item->{server},
                            num      => $win->{refnum},
                            itemname => $item->{name},
                            active   => $win->{data_level} > 0,
                            b_pos    => -1,
                            e_pos    => -1,
                           };
            }
        } else {
            #_debug_print "Error occurred reading info from window: $win";
            #_debug_print Dumper($win);
        }
    }

    @ret = _sort_windows(\@ret);

    return @ret;
}

sub _sort_windows {
    my $list_ref = shift;
    my @ret = @$list_ref;

    @ret = sort { $a->{num} <=> $b->{num} } @ret;

    return @ret;
}

sub ido_switch_select {
    my ($selected, $is_refnum) = @_;

    _debug_print "Selecting window: " . $selected->{name};

    Irssi::command("WINDOW GOTO " . $selected->{name});

    if ($selected->{type} ne 'WINDOW') {
        _debug_print "Selecting window item: " . $selected->{itemname};
        Irssi::command("WINDOW ITEM GOTO " . $selected->{itemname});
    }

}

sub ido_switch_exit {
    $ido_switch_active = 0;

    _print_clear();

    Irssi::gui_input_set($input_copy);
    Irssi::gui_input_set_pos($input_pos_copy);
    Irssi::signal_emit('change prompt', '', 'UP_INNER');
}

sub update_prompt {

    #TODO: refactor this beast.

    # take the top $ido_show_count entries and display them.
    my $match_num = scalar @search_matches;
    my $show_num = $ido_show_count;
    my $show_str = '(no matches) ';

    $show_num = $match_num if $match_num < $show_num;

    if ($show_num > 0) {
        _debug_print "Showing: $show_num matches";

        my @ordered_matches
         = @search_matches[$match_index .. $#search_matches,
                           0            .. $match_index - 1];

        my @show = @ordered_matches[0..$show_num - 1];

        # show the first entry in green

        unshift(@show, _format_display_entry(shift(@show), '%g'));

        # and array-slice-map the rest to be red.
        @show[1..$#show] = map { _format_display_entry($_, '%r') } @show[1..$#show];

        # join em all up
        $show_str = join ', ', @show;
    }

    # indicator if flex mode is being used (C-f to toggle)
    my $flex = sprintf(' [%s]', $ido_use_flex ? 'F' : 'E');

    my $search = '';
    $search = ' `' . $search_str . "'" if length $search_str;

    Irssi::signal_emit('change prompt',
                       $flex . $search . ' win: ' . $show_str,
                       'UP_INNER');
}

sub _format_display_entry {
    my ($obj, $colour) = @_;

    my $name = $obj->{name};
    if ($obj->{b_pos} >= 0 && $obj->{e_pos} > 0) {
        substr($name, $obj->{e_pos}, 0) = '%_';
        substr($name, $obj->{b_pos}, 0) = '%_';
        _debug_print "Showing name as: $name";
    }
    return sprintf('%s%d:%s%%n', $colour, $obj->{num}, $name);
}

sub _check_active {
    my ($obj) = @_;
    return 1 unless $active_only;
    return $obj->{active};
}

sub update_matches {

    @search_matches = get_all_windows() unless $search_str;

    if ($search_str =~ m/^\d+$/) {

        @search_matches =
          grep {
              _check_active($_) and $_->{num} =~ m/^\Q$search_str\E/
          } @window_cache;

    } elsif ($ido_use_flex) {

        @search_matches =
          grep {
              _check_active($_) and flex_match($_) >= 0
          } @window_cache;

    } else {

        @search_matches =
          grep {
              _check_active($_) and regex_match($_)
          } @window_cache;
    }

}

sub regex_match {
    my $obj = shift;
    return $obj->{name} =~ m/(.*?)\Q$search_str\E.*?/i
}

sub flex_match {
    my ($obj) = @_;

    my $pattern = $search_str;
    my $source  = $obj->{name};

    _debug_print "Flex match: $pattern / $source";

    # default to matching everything if we don't have a pattern to compare
    # against.

    return 0 unless $pattern;

    my @chars = split '', lc($pattern);
    my $ret = -1;

    my $lc_source = lc($source);

    foreach my $char (@chars) {
        my $pos = index($lc_source, $char, $ret);
        if ($pos > -1) {
            # store the beginning of the match
            $obj->{b_pos} = $pos if $char eq @chars[0];

            _debug_print("matched: $char at $pos in $source");
            $ret = $pos + 1;

        } else {

            $obj->{b_pos} = $obj->{e_pos} = -1;
            _debug_print "Flex returning: -1";

            return -1;
        }
    }

    _debug_print "Flex returning: $ret";

    #store the end of the match.
    $obj->{e_pos} = $ret;

    return $ret;
}

sub prev_match {

    $match_index++;
    if ($match_index > $#search_matches) {
        $match_index = 0;
    }

    _debug_print "index now: $match_index";
}

sub next_match {

    $match_index--;
    if ($match_index < 0) {
        $match_index = $#search_matches;
    }
    _debug_print "index now: $match_index";
}

sub get_window_match {
    return $search_matches[$match_index];
}

sub handle_keypress {
	my ($key) = @_;

    return unless $ido_switch_active;

    if ($key == 0) { # C-SPC?
        _debug_print "\%_Ctrl-space\%_";

        $search_str = '';
        @window_cache = @search_matches;
        update_prompt();

        Irssi::signal_stop();
        return;
    }

    if ($key == 3) { # C-C
        _print_clear();
        Irssi::signal_stop();
        return;
    }

    if ($key == 5) { # C-e
        $active_only = not $active_only;
        Irssi::signal_stop();
        update_matches();
        update_prompt();
        return;
    }

    if ($key == 6) { # C-f

        $ido_use_flex = not $ido_use_flex;
        _update_cache();

        update_matches();
        update_prompt();

        Irssi::signal_stop();
        return;
    }
    if ($key == 9) { # TAB
        _debug_print "Tab complete";
        print_all_matches();
        Irssi::signal_stop();
    }

	if ($key == 10) { # enter
        _debug_print "selecting history and quitting";
        my $selected_win = get_window_match();
        ido_switch_select($selected_win);

        ido_switch_exit();
        Irssi::signal_stop();
        return;
	}

    if ($key == 18) { # Ctrl-R
        _debug_print "skipping to prev match";
        #update_matches();
        next_match();

        update_prompt();
        Irssi::signal_stop(); # prevent the bind from being re-triggered.
        return;
    }

    if ($key == 19) {  # Ctrl-S
        _debug_print "skipping to next match";
        prev_match();

        #update_matches();
        update_prompt();

        Irssi::signal_stop();
        return;
    }

    if ($key == 7) { # Ctrl-G
        _debug_print "aborting search";
        ido_switch_exit();
        Irssi::signal_stop();
        return;
    }

    if ($key == 21) { # Ctrl-U
        $search_str = '';
        update_matches();
        update_prompt();

        Irssi::signal_stop();
        return;

    }

    if ($key == 127) { # DEL

        if (length $search_str) {
            $search_str = substr($search_str, 0, -1);
            _debug_print "Deleting char, now: $search_str";
        }

        update_matches();
        update_prompt();

        Irssi::signal_stop();
        return;
    }

    # TODO: handle esc- sequences and arrow-keys?

    if ($key == 27) { # Esc
        ido_switch_exit();
        return;
    }

    if ($key == 32) { # space
        my $selected_win = get_window_match();
        ido_switch_select($selected_win);
        Irssi::signal_stop();

        return;
    }

    if ($key > 32) { # printable
        $search_str .= chr($key);

        update_matches();
        update_prompt();

        Irssi::signal_stop();
        return;
    }

    # ignore all other keys.
    Irssi::signal_stop();
}

ido_switch_init();
