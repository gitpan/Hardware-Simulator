# Copyright (c) 1999 Greg Bartels. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package Hardware::Simulator;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw( Exporter );
@EXPORT = qw( );
@EXPORT_OK = qw( 
 &NewSignal &Responder &Repeater 
 &SimTime &EventLoop &TickEvent &Finish );

$VERSION = '0000.0005';

##############################################################
# global variables should not be accessed directly by external packages.
# use exported methods instead.
##############################################################

my $GLOBAL_UNIQUE_ID = 1; # a counter, used to identify each signal

my @GLOBAL_SENSITIVITY_LIST; # index = signal_id, value = anon list of code refs

my $GLOBAL_SIMULATION_TIME = 0; # current simulation time

my @GLOBAL_UPDATE_LIST; # list of signal objects to update at end of time slice

my $GLOBAL_PROCESS_BEING_EXECUTED=0;

my @GLOBAL_EVENT_QUEUE;

##############################################################

sub NewSignal
 {
 tie  $_[0], 'Hardware::Simulator', $GLOBAL_UNIQUE_ID++, $_[1] ;
 }

sub ReturnSignal  # this doesnt work
 {
 tie  my $temp, 'Hardware::Simulator', $GLOBAL_UNIQUE_ID++ ;
 return $temp;
 }


##############################################################
sub TIESCALAR
 {
 my ($class,$signal_id,$initial_val)=@_;
 my $rhash={
   'current_value'=>$initial_val,
   'next_value'=>$initial_val,
   'signal_id'=>$signal_id,
   'Event'=>0
   };
 return bless $rhash, $class;
 }

sub FETCH
 {
 my ($w)=@_;
 return $w->{'current_value'};
 }

sub STORE
 {
 my ($w,$val)=@_;

 if ($val eq 'Event') 
  {
  my $event = $w->{'Event'}; 
  return $event;
  }

 if ($GLOBAL_PROCESS_BEING_EXECUTED)
  {
  $w->{'next_value'}=$val;
  push(@GLOBAL_UPDATE_LIST,$w);
  $w->{'Event'}=1;
  }
 else
  {
  $w->{'next_value'}=$val;
  $w->{'current_value'}=$val;
  }

 schedule_events_sensitive_to_this_signal($w->{'signal_id'});
}

sub TickEvent
{
  my $tied = tied($_[0]);
  return $tied->{'Event'};
}

##############################################################

sub schedule_events_sensitive_to_this_signal
{
 my ($signal_id)=@_;
 my $list_ref = $GLOBAL_SENSITIVITY_LIST[$signal_id];
 return unless (defined($list_ref));
 return unless (@$list_ref);
 foreach my $sub_ref (@$list_ref)
  {
  add_event($GLOBAL_SIMULATION_TIME,$sub_ref);
  }
}

sub using_event_queue_sort_routine
  {return $$a[0] <=> $$b[0];}

sub add_event
{
	# when represents the simulation time when the event will be performed.
	# what represents the event to perform (a code reference).
	my($when,$what)=@_;
	my @when_what = ($when,$what);
	unshift(@GLOBAL_EVENT_QUEUE,\@when_what);

	# if adding an event for 'NOW' then dont need to sort the array
	unless ($when == $GLOBAL_SIMULATION_TIME)
		{
		@GLOBAL_EVENT_QUEUE = 
		sort using_event_queue_sort_routine @GLOBAL_EVENT_QUEUE;
		}
}

sub SizeOfEventQueue
{
	return scalar(@GLOBAL_EVENT_QUEUE);
}

sub get_event
{
	my $list_ref = shift(@GLOBAL_EVENT_QUEUE);
	return @$list_ref;
}

##############################################################
# Responder ( [list of sensitive signals], sub ref)
##############################################################
sub Responder
{
 my $sub_ref = pop(@_);

 my $max = scalar(@_);
 my ($tied_object, $signal_id);
 my $list_size = scalar(@GLOBAL_SENSITIVITY_LIST);

 #########################################################
 # for every signal in sensitivity list for this process,
 # update global sensitivity list so that we will know to call
 # this process when sensitive signal changes.
 #########################################################
 for(my $i = 0; $i<$max; $i++)
	{
	$tied_object = tied($_[$i]);
	$signal_id = $tied_object->{'signal_id'};

	#########################################################
	# if there isn't an entry in global sensitivity list for
	# this signal, then create one.
	#########################################################
	unless(defined($GLOBAL_SENSITIVITY_LIST[$signal_id]))
		{
		my @new_list;
		$GLOBAL_SENSITIVITY_LIST[$signal_id] = \@new_list;
		}

	push (@{$GLOBAL_SENSITIVITY_LIST[$signal_id]},$sub_ref);

	}


 #########################################################
 # if sensitivity list is empty, 
 # schedule this process to start immediately
 #########################################################
 unless($max)
	{
	add_event (0,$sub_ref);
	}

} 

##############################################################
# Repeater ( period, sub ref)
##############################################################
sub Repeater
{
 my ($period,$sub_ref) = @_;
 add_event($GLOBAL_SIMULATION_TIME , $sub_ref);
 add_event($GLOBAL_SIMULATION_TIME + $period, sub{ Repeater($period, $sub_ref); });
}


##############################################################
# Finish
##############################################################
sub Finish
{
 @GLOBAL_EVENT_QUEUE = ();
}


##############################################################
# given signals and processes that manipulate these signals,
# event_loop is called to process all events until the event queue 
# is empty. 
##############################################################
sub EventLoop
{
	ProcessEndOfTimeSlice();
	while(SizeOfEventQueue())
		{ ProcessOneEvent(); }
}


sub ProcessOneEvent
{
	my ($next_time, $next_process) = get_event();
	if ($next_time > $GLOBAL_SIMULATION_TIME)
		{ ProcessEndOfTimeSlice(); }
	$GLOBAL_SIMULATION_TIME = $next_time;
	$GLOBAL_PROCESS_BEING_EXECUTED = $next_process;
	&$next_process;
	$GLOBAL_PROCESS_BEING_EXECUTED = 0;
}


sub ProcessEndOfTimeSlice
{
	# at the end of any time slice, update signals so that
	# there current value is assigned to their next value.
	while(@GLOBAL_UPDATE_LIST)
		{
		my $signal_object = pop(@GLOBAL_UPDATE_LIST);
		$signal_object->{'current_value'} = 
		$signal_object->{'next_value'};
		$signal_object->{'Event'}=0;
		}
}

sub SimTime
{
	return $GLOBAL_SIMULATION_TIME;
}




1;
__END__

=head1 NAME

Hardware::Simulator - Perl extension for Perl Hardware Descriptor Language

=head1 SYNOPSIS

  use Hardware::Simulator;

  # NewSignal( perl_variable [, initial_value]);
  # create a signal called $in_clk, give it an initial value of 1
  NewSignal(my $in_clk,1);

  # Repeater ( time_units , code_ref)
  # every time_units, call the code reference, starting at the current time
  Repeater ( 5, sub{if ( $in_clk==0) { $in_clk=1;} else { $in_clk=0;}});

  # Responder ( [signal_name ... signal_name], code_ref );
  # respond to any changes to signals by calling code reference.
  # any time out_clk changes, print value of clock and simulation time.
  Responder ( $out_clk,  sub
  {
    my $time = SimTime();
    print "out_clk = $out_clk. time=$time\n";
  });

  # start processing of events and event scheduling.
  EventLoop();

=head1 DESCRIPTION

Hardware::Simulator ==> a Perl Hardware Descriptor Language

Hardware::Simulator is a lightweight version of VHDL or Verilog HDL.
All of these languages were developed as means to
describe hardware. 

Hardware::Simulator was created as a means to quickly prototype a basic 
hardware design and simulate it. VHDL and Verilog are both
restrictive in their own ways. Hardware::Simulator was created to quickly
put something together as a "proof of concept", to show that 
a design concept would work or not. and then the design
could be translated to VHDL or Verilog.

The problem that started all of this was designing a fifo for a video 
scaling asic. The chip used a buffer to store incoming video data. The asic 
read the buffer to generate the outgoing video image. We estimated
how large we thought the buffer needed to be, but we wanted to 
confirm that our numbers were right by running simulations.

The problem was we needed to run hundreds of different simulations,
given the permutations of input image formats, output image formats,
and input/output clock frequencies. We also had text files containing
valid formats and frequencies. A text file as input called for perl
to manipulate, split, format, and extract the data properly.

This data then had to be translated onto the a HDL simulation.
The problem was that there was no easy way to write a perl script
that would simulate hardware, so the only solution was to have perl
drive a Verilog simulator and pass all these parameters via 
command line parameters. so then verilog files had to be created,
and the simulator had to be driven, and the end result was a lot
of work to simulate a simple fifo.

Time contraints did not allow me to develop a HDL package for perl
to solve the original problem, but I took it on in my spare time.
and eventually Hardware::Simulator was born.

quick lesson of the competition:

VHDL was developed as part of a government program
to develop a standard language for describing the
functionality and structure of IC's. 
It became an IEEE standard in 1987.
The VHDL acronym comes from combining 
VHSIC (Very High Speed Integrated Circuits) with 
HDL (Hardware Descriptor Language).

Verilog HDL was a propietary language developed by 
Gateway Design Automation in 1984. 
Verilog HDL was placed in the public domain in 1987.

Note that VHDL and Verilog have been around for a while,
and if you wish to do ASIC design in an HDL, you will eventually
need to use either VHDL or Verilog. Tools are available to take
VHDL and/or Verilog files and "synthesize" them into a file
describing an ASIC at the gate level. it is this gate level
file that is used by the asic foundry to put silicon in the 
right places. Hardware::Simulator has no synthesis tool ...yet ;) ... so it
is only useful to architect a design and prove it works,
before translating it into VHDL or Verilog. 

back to Hardware::Simulator:

Perl HDL is a perl package used to provide the 
basic capabilities needed to simulate the parallelism
of hardware, versus the singular processing of a 
software language.  Here's a brief example of code 
which uses this parallelism:

####################################################################3
use Hardware::Simulator;

# declare signals and regular variables

NewSignal(my $in_clk,1);
NewSignal(my $out_clk,1);

# create hardware (parallel) logic

Repeater ( 5, sub{
	if ( $in_clk==0) 
		{ $in_clk=1;} 
	else 
		{ $in_clk=0;}
	print "in_clk = $in_clk\n";
});
Repeater (13, sub{
	if ($out_clk==0) 
		{$out_clk=1;} 
	else 
		{$out_clk=0;}
	print "out_clk = $out_clk\n";
});

# start processing the hardware events.
EventLoop();
####################################################################3

The first thing the Hardware::Simulator module does is introduce the notion 
of time and parallelism. Software generally is only concerned with "now".
Hardware  has all of its logic operating simultaneously. To keep track of 
it all, hardware "events" are "scheduled". Multiple events may be scheduled at 
the same time, or independent of one another. 

One way to schedule events in Hardware::Simulator is with the Repeater
subroutine:

Repeater( time_period, code_ref);

The Repeater routine takes two parameters, an integer and
a subroutine reference. The integer indicates how often to do something.
(it can represent seconds, or nanoseconds, or fortnights, the units
are up to you). The code reference indicates what to do when the time
has passed.

In the above example, there are two clock generators, coded using the
Repeater subroutine. One call says "every 5 time units, invert in_clock".
The other Repeater routine says "every 13 time units, invert the out_clock".
Once these two routines are called, the EventLoop can be called, and
the clock signals will be generated independent of one another.

The above example shows both the concept of simulation time and
parallelism. If you run the above example, you would see in_clk and
out_clk toggling at their assigned periods, in_clk every 5 units, 
out_clk every 13 units. This means that in_clk might toggle 2 or 3 times
for every time that out_clk toggled.

The concept of simulation time is derived from this. Simulation time
starts at time zero. From time zero, events are scheduled to reflect 
how much time into the future they will occur. In the above example,
the Repeater routine schedules in_clk to be toggled at time 0, 5, 10, 15
time units, etc. In comparison, the second Repeater routine schedules out_clk
to be toggled at time 0, 13, 26, 39 time units, and so on.

Note that simulation time is a concept, independent of cpu time or
the value returned by the `time` function. Simulation time might
be 30, and then the next event scheduled to execute at time 42, so simulation
time is immidiately advanced to 42, and the event is executed.

The EventLoop routine takes care of the event scheduling and event
execution. The end result is that in_clk and out_clk are toggled
in parallel with one another, as independent pieces of code.
And that this is accomplished by introducing the concept of simulation time.

Note that at time 65, both routines will be executed. 
The EventLoop routine will see multiple events scheduled for the same 
time and must serialize them, and execute them one at a time. The order 
in which the events are executed for the same simulation time are 
indeterminant. 

This happens whether you use Hardware::Simulator, VHDL, or Verilog,
and is a reflection of the underlying hardware. The difference is that
it is possible to simulate something and get the right answer by
chance, and then have the real hardware be non-functional. 
It is up to the designer to write code that is not susceptible to this problem.
(designer beware)

multiple events within the same simulation time will be executed within
different "time slices" within that simulation time. At time 65, there
will be two time slices, one for Repeater in_clk, and one for Repeater out_clk.
Which order they get executed in is indeterminant.


###

another concept introduced by HDL's is the concept of "sensitivity".

Hardware examples of this are flip-flops which have data and a clock as
input, and a Q-output.  The flip-flop output changes only when the clock
input goes from a zero to a one. Changes of the data input do not affect
the Q-output, except that the data value is captured when the clock goes
high, copied to the q-output, and frozen there until the next clock edge.

The flip-flop is said to be "sensitive" to the clock signal, and not 
sensitive to the data signal.

another example would be an "AND" gate. An AND gate has two inputs.
A change on either input causes the output to change. The AND gate
is therefore "Sensitive" to both its inputs.

HDL's use sensitivity as another means to schedule events 
(in addition to scheduling events based on absolute times, etc).

In Hardware::Simulator, this is accomplished with the "Responder" subroutine.

Responder( [sensitivity_list], code_ref);

The sensitivity list is a list of "Signals" (explained below), which 
the Responder will monitor. whenever any of these signals change, the 
Responder will schedule the code_ref to execute "immediately".
If no sensitivity list is provided, the code_ref is executed once at
simulation time zero.

"Immediately" is quoted, because if Responder1 is executing
and causes a signal to change which triggers Responder2, then
the Responder2 is SCHEDULED to execute, but will not actually 
execute until (at the earliest) Responder1 has completed.
(they will execute at the same "Simulation time" but within different
"time slices").

In VHDL, sensitivity is implemented using "process"es.
In Verilog, sensitivity is implemented using "always" blocks.

###

The word "Signals" is quoted because that is yet another concept of 
Hardware::Simulator.

The NewSignal subroutine takes a perl scalar variable and turns it
into a Hardware::Simulator signal. (note that only perl scalar's are 
currently supported. you cannot make hashes or lists into signals. 
hopefully this can be fixed in the future).

NewSignal(my $in_clk,1);

The syntax is NewSignal( perl_scalar_variable [, initial_value]);

A sensitivity list is a list of signals, so at a minimum, if you have
any Responders, you must have signals declared for the sensitivity list.

in the below example, the clocks are signals, clk_in and clk_out.
These signals are driven by the Repeater routine as before. Three responders
have been added to this example, though. two of which have in_clk in its
sensitivity list, and one has out_clk in its sensitivity list.
Anytime in_clk changes, the two responders are scheduled for execution.
Anytime out_clk changes, its responder is scheduled for execution.

Here's the code:

#######################################################################
use Hardware::Simulator;

# declare signals and regular variables

NewSignal(my $in_clk,1);
NewSignal(my $in_data,42);

NewSignal(my $out_clk,0);

my @fifo;

# create hardware (parallel) logic

Repeater ( 5, sub{if ( $in_clk==0) { $in_clk=1;} else { $in_clk=0;}});
Repeater (13, sub{if ($out_clk==0) {$out_clk=1;} else {$out_clk=0;}});

Responder ( $in_clk,  sub
{
	$in_data++;
	push(@fifo,$in_data);

	my $time = SimTime();
	print "time=$time \t push $in_data \n";

	if (scalar(@fifo) > 5)
		{print "\n\nfifo reached maximum\n\n"; ; }
});

Responder ( $out_clk,  sub
{
	my $out_data = shift(@fifo);
	my $time = SimTime();
	print "time=$time \t\t\t\t shift $out_data \n";
});

EventLoop();

#######################################################################

The above code implements a simple fifo. Every positive edge of in_clk
causes a new value to be pushed onto the @fifo list. Every positive edge
of out_clk causes a value to be shifted off the @fifo list. The code will
run until there are 5 items in the fifo, indicating fifo overflow.

Any change in a signal in a responder's sensitivity list causes the
code reference for that responder to be scheduled. Signals are used for this
because they use Perl's built in 'TIE' method so that any assignment
to the variable causes the responder event to be scheduled.

This is the only reason that perl variables cannot be used in sensitivity 
lists.

Signals can be passed to the TickEvent subroutine of Hardware::Simulator.
The return value is true or false, indicating whether or not that
signal has changed yet during this simulation time.
To have code that only works on positive edge of clock, you could do this:

	unless (TickEvent($in_clk) and ($in_clk)) {return;}

	# else its a positive edge, continue processing.

VHDL implements this using 'event, which is where the Hardware::Simulator 
name comes from. Verilog implements a limited version of this based on @signal, 
but this can only be used in certain places within verilog. TickEvent and 'event
can be used anywhere.

also, note that both responders use a perl variable (@fifo) which is
shared between them. you can share perl variables between processes.
A signal is only used to trigger a responder, or to detect TickEvents.
Also, note that signals can currently only be scalars, so any
data that is not a scalar cannot be a signal, it must be a perl variable.

There is one other concept associated with signals, and its probably the 
trickiest concept in HDL's. at the beginning of a time slice, 
all signal values are frozen. Any updates to signals do not actually
occur until the last time slice is executed for that simulation time.
this is not very intuitive at first glance, but it has its uses in
the hardware world.

For example, a hardware pipeline may have 4 signals, 
say a,b,pipe_output, and pipe_input.
These signals may represent four registers within a pipeline.
so the code might look like this:


Responder ( $out_clk,  sub
{
	$pipe_output = $a;
	$a = $b;
	$b = $pipe_input;
});

if variables are used, all four values are updated as each line
is executed. if signals are used, then all four values are scheduled
to be updated when the simulation time changes, which is after all
responders are finished for this simulation time. so if signals are
used, the order of assignment doesn't matter. You would get
the same functionality if you said:

Responder ( $out_clk,  sub
{
	$b = $pipe_input;	# order independent.
	$pipe_output = $a;
	$a = $b;
});

This is a lesson that you will not truly learn until you write
code that doesn't work the way you expected because you expected
the signal to be updated immediately. you might have to do this
several times before the point is permanently etched into your brain.
here's a short example:

Responder ( $out_clk,  sub
{
	$sig = 0;
	print "Expect sig to be zero. sig is $sig \n"; 
}

and it prints out something other than zero. what it is printing out is
the value of sig before it entered the responder. sig will not get set 
to the value of zero until the responder is finished.

REMEMBER: 
signal assignments will not take effect until simulation time changes.
until that happens, all reads from signals will read the value
the signal had at the beginning of that simulation time.

if you want something to update immediately, it must be a normal 
perl variable.

As I said, this part is non-intuitive stuff, but both Verilog and VHDL support
this functionality in some way, so it is included in Hardware::Simulator.
VHDL uses signals and variables, the same as Hardware::Simulator does.
Verilog uses blocking and non-blocking assignments.


###

shortcomings of Hardware::Simulator:

One shortcoming of Hardware::Simulator is that it does not support delay statements
within a responder callback. 

VHDL might say this:

process(sensitive_signal)	-- process 1
begin
	wait for 10 ns;		-- time 10
	sig2 = 2;
	wait for 10 ns;		-- time 20
	sig4 = 4;
end process

process(sensitive_signal)	-- process 2
begin
	wait for 5 ns;		--time 5
	sig1 = 1;
	wait for 10 ns;		-- time 15
	sig3 = 3;
end process;

VHDL will handle this properly by calling both processes when 
the sensitive_signal changes. when it hits a wait statement within
a process, the remaining code of the process is scheduled to be
executed at a later time. it then moves on to whatever is next.
the event schedule would look like this:

sensitive_signal changes at time 0;
sig1 = 1 at time 5;	(process 2)
sig2 = 2 at time 10;	(process 1)
sig3 = 3 at time 15; 	(process 2)
sig4 = 4 at time 20;	(process 1)

Hardware::Simulator is currently unable to execute part of a 
subroutine reference,stop in mid-execution, execute part of 
another subroutine, stop in mid-execution, the return to where 
it left off in the first subroutine (with all signals and variables 
in tact), and continue execution at that point. 

You'll notice that Hardware::Simulator does not have a "WaitFor" 
routine of any kind. any time based event must be scheduled with 
a "Repeater" routine. All Hardware::Simulator events are singular 
subroutine references. once an event is scheduled and begins execution, 
it cannot stop until it is complete.

This should not be an issue for proof-of-concept code, for prototyping,
or for architecture work, but it means that you could have hard time
translating VHDL or Verilog code into Hardware::Simulator.  
Hardware::Simulator is currently a subset of VHDL and Verilog.

Any suggestions for fixing this problem within Perl would be welcome.
It is basically a problem with getting Perl to be able to handle multiple,
simultaneous calls to subroutines, which just might not be possible
to get around. the only other solution, which would require a complete
rewrite of Hardware::Simulator.pm, is to translate HDL code into a form 
that can handle jumping around from one spot to another (basically, a 
bunch of labels and goto statements). hopefully a more elegant solution 
is possible.

using "fork" seems overkill for this problem. 
perhaps when "threads" get implemented into perl, that will provide
a solution.

###

=head1 AUTHOR

Greg Bartels,  gbartels@xli.com

=head1 SEE ALSO

perl(1).

=cut
