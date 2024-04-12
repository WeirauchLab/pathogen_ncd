{{ pub.title }}
==============================================================================

{{ pub.authorlastname }} et al., {{ pub.publicationname}}, {{ pub.year}}.
{{ pub.url }}

Database release {{ data.build }}, {{ data.releasedate }}
{{ site.publicurl }}/data


Included files
--------------

  {{ site.basename }}.tsv      tab-delimited text, UTF-8, LF line endings
  {{ site.basename }}.html     XML/HTML table fragment
  {{ site.basename }}.sqlite3  SQLite 3 database


Contacts
--------

{% for c in pub.contacts -%}
- {{ c.name }} <{{ c.email }}>
{% endfor %}
