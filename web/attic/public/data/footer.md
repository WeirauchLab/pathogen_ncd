The `pathogen_ncd-supplement.zip` archive contains of the **supplemental tables**
included with the [_medRxiv_ (2023) publication][0].

If you want **just the underlying data**, in all the various formats, in one
compressed bundle, download the latest `pathogen_ncd-db-build-*.zip` if you are on
Windows; download the .tar.gz version if you are on Mac or Linux.

## Contents of the .zip file

* a README file containing the current DB release version and date, with links
  to the <em>medRxiv</em> (2023) paper and this site

* the **`.tsv` (tab-separated values) file** is suitable for import into any
  spreadsheet program, *e.g.*, Excel or LibreOffice Calc

    * it is UTF-8-encoded, no text field delimiters (no quotes), with
      **DOS/Windows (CR+LF) [line endings][1]**; don't try to process this file
      with Unix utilities like `cut` or `awk` without converting line endings
      first!

* the **`.sqlite3` file** is a relational database that can be queried
  using the SQLite 3 library provided in most programming languages' standard
  libraries ([example for Python][2]), using a graphical tool such as
  [DB Browser for SQLite][3], or a web-based tool such as [Datasette][4].

    * **We recommend [Datasette][4] for this purpose** because it builds basic
      SQL (Structured Query Language) queries for you with a point-and-click
      web interface, which you can further refine, making it a good SQL
      learning tool.

* the **`.html` file** is the same data data, simply reformatted into an unstyled
  HTML fragment.

    * this file has a root `<table>` element, so it can even be processed
      with a tolerant XML parser

## Contents of the .tar.gz file

* same as above, except text files have **Unix (LF) line endings** and the
  tarball extracts to its own subdirectory, named after the database build.

## Validating MD5 checksums

```bash
# assuming Bash shell on Linux
md5sum -c <(curl https://tf.cchmc.org/pubs/lape2023/data/MD5SUMS)
```

[0]: https://www.medrxiv.org/content/10.1101/2023.09.14.23295428v1
[1]: https://en.wikipedia.org/wiki/Newline
[2]: https://docs.python.org/3/library/sqlite3.html "sqlite3 — DB-API 2.0 interface for SQLite databases"
[3]: https://sqlitebrowser.org/
[4]: https://datasette.io/
