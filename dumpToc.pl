#!/usr/bin/perl

=comment

Copyright (c) 2012, Andrew Dunstan

Licenced under the terms of The PostgreSQL Licence.

See accompanying LICENSE file for details.

=cut

use strict;
use IO::Handle;
use Getopt::Long;
use File::Path qw(make_path);

my ($format,$destdir,$dumpfile,$help, $tocfile);

GetOptions ("format=s" => \$format, 
            "destdir=s" => \$destdir, 
            "dumpfile=s" => \$dumpfile,
			"tocfile=s" => \$tocfile,
            "help" => \$help)
    || die "Bad options";

help() if $help;

my @formats = qw(Unknown Custom Files Tar Null Directory);
my @sections = qw(None PreData Data PostData);
my $result = [];
my $toc = [];

my %globs;

my ($magic, $byte);
my $inh;
my $runscript;
my %fnames;

if ($tocfile && $dumpfile)
{
	die "tocfile and dumpfile options are mutually exclusive";
}

if (@ARGV)
{
	die "dumpfile already given" if $dumpfile;
	$dumpfile = shift(@ARGV);
}

my $src = $dumpfile;
$src ||= $tocfile;

if ($src)
{
	open($inh,$src) || die "opening $src: $!";
}
else
{
	$inh = IO::Handle->new_from_fd(fileno(STDIN),"r"); 
}

# load optional output modules
if ($format eq 'YAML')
{
	require YAML;
}
elsif ($format eq 'Dumper')
{
	require Data::Dumper;
}

# get the actual data
# fills in @$result and @$toc

read_data();

# output the data
if ($format eq 'YAML')
{
	print YAML::Dump($result);
}
elsif ($format eq 'Dumper')
{
	print Data::Dumper::Dumper($result);
}
else
{

	if ($destdir)
	{
		make_path($destdir);
		chdir $destdir;
	}

	open($runscript,">runalldump._sql");

	write_entry($_) foreach (@$toc);
}

exit;

########################################################################

sub write_entry
{
	my $te = shift;
	my @lst;
	my $n = 1;
	@lst = (grep {exists $_->{schema} } @$te); 
	my $schema = $lst[0]->{schema};
	@lst = (grep {exists $_->{tag} } @$te);
	my $tag = $lst[0]->{tag};
	@lst = (grep {exists $_->{desc} } @$te);
	my $desc = $lst[0]->{desc};
	return if $desc eq 'TABLE DATA';
	@lst = (grep {exists $_->{defn} } @$te);
	my $defn = $lst[0]->{defn};
	my $fname = '';
	$fname = "$schema." if  $schema;
	$fname = "$fname$tag.$desc.sql";
	$fname =~ s/[ ()]/_/g;
	# This is a bit of a crock. We need something better
	# and more deterministic than this.
	# at least we need to build in the parent name for
	# some objects (FKs, triggers). The trouble is
	# there's really not enough info in the object
	# metadata.
	$fname =~ s/(\.\d+)?\.sql$/'.' . $n++ . '.sql'/e 
	  while (exists $fnames{$fname});
	$fnames{$fname}  = 1;
	my $outh;
	open($outh,">$fname");
	print $outh $defn;
	close($outh);
	print $runscript "\\i $fname\n";
}

sub ReadInt
{
	my $sign;
	my $val = 0;
	my $bytes;
	sysread $inh,$sign,1;
	$sign= unpack("C",$sign);
	sysread $inh,$bytes,$globs{intSize};
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
	sysread $inh,$bytes,1; # flag we don't care about for now.
	my $val = 0;
	sysread $inh,$bytes,$globs{offSize};
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
	sysread $inh,$val,$len if $len > 0;
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
	push @$toce, {section=>$sections[ReadInt() - 1]};
	push @$toce, {defn=>ReadStr()};
	push @$toce, {dropStmt=>ReadStr()};
	push @$toce, {copyStmt=>ReadStr()};
	push @$toce, {namespace=>ReadStr()};
	push @$toce, {tablespace=>ReadStr()};
	push @$toce, {tableam=>ReadStr()} if $globs{vmin} >= 14;
	push @$toce, {relkind=>chr(ReadInt())} if $globs{vmin} >= 16;
	push @$toce, {owner=>ReadStr()};
	push @$toce, {withOids=>ReadStr()};
	
	my $deps = [];
	push @$toce, {dependencies=>$deps};

	while (my $dep = ReadStr())
	{
		push @$deps, $dep;
	}

    if ($globs{format} eq 'Custom')
    {
        push @$toce, {extra_offset => ReadOffset()};
    }
    else
    {
        push @$toce, {file_name => ReadStr()};
    }

	return $toce;

}

sub read_data
{


	sysread $inh,$magic,5;
	sysread $inh,$byte,1; $globs{vmaj} = unpack("C",$byte);
	sysread $inh,$byte,1; $globs{vmin} = unpack("C",$byte);
	sysread $inh,$byte,1; $globs{vrev} = unpack("C",$byte);
	sysread $inh,$byte,1; $globs{intSize} = unpack("C",$byte);
	sysread $inh,$byte,1; $globs{offSize} = unpack("C",$byte);
	sysread $inh,$byte,1; $globs{format} = $formats[unpack("C",$byte)];

	push @$result, {magic=>$magic}, {meta=>\%globs};
	if ($globs{vmin} >= 15)
	{
		sysread $inh,$byte,1;
		push @$result, {compression=>unpack("C",$byte)};
	}
	else
	{
		push @$result, {compression=>ReadInt()};
	}
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

}

sub help
{

	print STDERR "$0: [ --help | --format=format | --destdir=destdir ] [ [--dumpfile=|--tocfile=]dump_or_toc_file ]\n";
	exit 0;
}
