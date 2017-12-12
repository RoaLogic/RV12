#!/usr/bin/perl


# print "Latex PreProcessor v0.1\n";

my @defines = qw/MARKDOWN/;
my @if   = qw/0/;
my @skip = qw/0/;


#Go through input files
while (<>) {
  chomp;
#  print $_;

  #get rid of comments; they mess up the checks
  s/%.*//;


  #check for new define
  if (/\\newcommand\*{\\(\w+)}{}/) {
    push @defines, $1;
    next;
  }


  #check for if
  if (/\\ifdefined\\(\w+)/) {
    my $index = 0;
    ++$index until $defines[$index] == $1 or $index > $#defines;

    if ($index > $#defines) {
      #value not found
      unshift @skip, 1;
    } else {
      #value found
      unshift @skip,0;
    }

    #found an if
    unshift @if,1;

    next;
  }


  #check for else
  if (/\\else/) {
    die "ELSE without IF\n" if $if[0] == 0;

    if ($skip[0] == 0) {
      $skip[0] = 1;
    } else {
      $skip[0] = 0;
    }

    next;
  }


  #check for end-if
  if (/\\fi\s*$/) {
    die "FI without IF\n" if $if[0] == 0;

    shift @if;
    shift @skip;

    next;
  }


  #write string
  print "$_\n" unless $skip[0];
}

