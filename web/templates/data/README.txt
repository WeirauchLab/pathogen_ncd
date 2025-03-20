{{ pub.title }}
==============================================================================

{{ pub.author.surname }} et al., {{ pub.journal}}, {{ pub.year}}.
{{ pub.url }}


Included files
--------------

The line endings for the `.tsv` files are Unix linefeeds. These tab-delimited
files are intended for post-processing in the Unix shell environment with "Unix
toolbox" utilities like `cut`, `sort`, and `awk`.

Excel `.xlsx` files are provided for any other uses.

Compressed archives containing results datasets in both formats are available
for download from {{ site.deploy.publicurl }}.


Contacts
--------

{% for c in pub.contacts -%}
- {{ c.name }} <{{ c.email }}>
{% endfor %}
