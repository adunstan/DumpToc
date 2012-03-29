# Dump Table of Contents of a PostgreSQL non-text dump.

The input can be a Custom Format dump file, or the toc.dat file from a Tar or Directory Format dump.


``` dumpToc.pl [ --help | --format=format | --destdir=destdir ] [--dumpfile=|--tocfile=]dump_or_toc_file ] ]
```

format can be Dumper or YAML

If format is not specified, sql files are generated.

destdir says where to put the files.

