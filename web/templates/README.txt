{{ pub.propername }}
==============================================================================

{{ pub.authorlastname }} et al., {{ pub.publicationname}}, {{ pub.year}}.
PUBURL

Database release {{ site.db.build }}, {{ site.db.releasedate }}
{{ site.publicurl }}/data


Included files
--------------

  {{ pub.shortname }}.tsv      tab-delimited text, UTF-8-encoded, no quotes
  {{ pub.shortname }}.html     XML/HTML table fragment
  {{ pub.shortname }}.sqlite3  SQLite 3 database

Line endings for the .tsv and .html files are those appropriate for Windows
(CR+LF) if you downloaded the .zip version; those appropriate for Linux, Mac,
or other Unix (LF) if you downloaded the .tar.gz version.


Contacts
--------

{{ pub.contacts[0].name }} <{{ pub.contacts[0].email }}>
{{ pub.contacts[1].name }} <{{ pub.contacts[1].email }}>
