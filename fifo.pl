# Copyright (c) 1999 Greg Bartels. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use strict;

use Hardware::Simulator 
  qw ( NewSignal Responder Repeater SimTime EventLoop TickEvent Finish );


# declare signals and regular variables

NewSignal(my $in_clk,1);
##my $in_clk = PHDL::ReturnSignal;


NewSignal(my $in_data,1);

NewSignal(my $out_clk,0);

my @fifo;
my $count = 0;

# create hardware (parallel) logic

Repeater ( 10,sub{if ( $in_clk==0) { $in_clk=1;} else { $in_clk=0;}});
Repeater (33, sub{if ($out_clk==0) {$out_clk=1;} else {$out_clk=0;}});

Responder ( $in_clk,  sub
{
	# only work on positive edge of clock
	unless (TickEvent($in_clk) and ($in_clk)) {return;}

	$in_data++;
	push(@fifo,$in_data);

	my $time = SimTime();
	print "time=$time \t push $in_data \n";

	if (scalar(@fifo) > 20)
		{print "\n\nfifo reached maximum\n\n"; Finish(); }
});

Responder ( $out_clk,  sub
{
	unless (TickEvent($out_clk) and ($out_clk)) {return;}
	my $out_data = shift(@fifo);

	my $time = SimTime();
	print "time=$time \t\t\t\t shift $out_data \n";

});

EventLoop(); # keep running events until run out or someone calls Finish();

print "end of EventLoop \n";
