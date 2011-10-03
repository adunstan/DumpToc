#!/usr/bin/perl

use strict;
use YAML;
my @formats = qw(Unknown Custom Files Tar Null Directory);
my @sections = qw(None PreData Data PostData);
my $result = [];
my $toc = [];

my %globs;

my ($magic, $byte);

sysread STDIN,$magic,5;
sysread STDIN,$byte,1; $globs{vmaj} = unpack("C",$byte);
sysread STDIN,$byte,1; $globs{vmin} = unpack("C",$byte);
sysread STDIN,$byte,1; $globs{vrev} = unpack("C",$byte);
sysread STDIN,$byte,1; $globs{intSize} = unpack("C",$byte);
sysread STDIN,$byte,1; $globs{offSize} = unpack("C",$byte);
sysread STDIN,$byte,1; $globs{format} = $formats[unpack("C",$byte)];

push @$result, {magic=>$magic}, {meta=>\%globs};
push @$result, {compression=>ReadInt()};
push @$result, {sec=>ReadInt()};
push @$result, {min=>ReadInt()};
push @$result, {hour=>ReadInt()};
push @$result, {mday=>ReadInt()};
push @$result, {mon=>(1+ ReadInt())};
push @$result, {yr=>(1900 + ReadInt())};
push @$result, {isdst=>ReadInt()};
push @$result, {dbname=>ReadStr()};
push @$result, {remoteVersion=>ReadStr()};
push @$result, {pgdumpVersion=>ReadStr()};
my $tocCount = ReadInt();
push @$result, {tocCount=>$tocCount};
push @$result, {toc=>$toc};

push @$toc, readTocEntry() foreach (1..$tocCount);

print Dump($result);


sub ReadInt
{
	my $sign;
	my $val = 0;
	my $bytes;
	sysread STDIN,$sign,1;
	$sign= unpack("C",$sign);
	sysread STDIN,$bytes,$globs{intSize};
	# ints are written least significant byte first
	# so we get them reverse order using pop()
	my @b = unpack("C*",$bytes);
	while (@b)
	{
		my $v = pop @b;
		$val = ($val << 8) + $v;
	}
	$val = -$val if ($sign);
	return $val;
}

sub ReadOffset
{
	
	my $bytes;
	sysread STDIN,$bytes,1; # flag we don't care about for now.
	my $val = 0;
	sysread STDIN,$bytes,$globs{offSize};
	# offsets are written least significant byte first
	# so we get them reverse order using pop()
	my @b = unpack("C*",$bytes);
	while (@b)
	{
		my $v = pop @b;
		$val = ($val << 8) + $v;
	}
	return $val;
}


sub ReadStr
{
	my $len = ReadInt();
	my $val = "";
	sysread STDIN,$val,$len if $len > 0;
	return $val;
}

sub readTocEntry
{

	my $toce = [];
	push @$toce, {dumpId=>ReadInt()};
	push @$toce, {dataDumper=>ReadInt()};
	push @$toce, {tableoid=>ReadStr() +0};
	push @$toce, {oid=>ReadStr() +0};
	push @$toce, {tag=>ReadStr()};
	push @$toce, {desc=>ReadStr()};
	push @$toce, {section=>$sections[ReadInt()]};
	push @$toce, {defn=>ReadStr()};
	push @$toce, {dropStmt=>ReadStr()};
	push @$toce, {copyStmt=>ReadStr()};
	push @$toce, {namespace=>ReadStr()};
	push @$toce, {tablespace=>ReadStr()};
	push @$toce, {owner=>ReadStr()};
	push @$toce, {withOids=>ReadStr()};
	
	my $deps = [];
	push @$toce, {dependencies=>$deps};

	while (my $dep = ReadStr())
	{
		push @$deps, $dep;
	}

	push @$toce, {extra_offset => ReadOffset()};

	return $toce;

}
