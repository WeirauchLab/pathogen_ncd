{{ pub.title }}
==============================================================================

{{ pub.author.surname }} et al., {{ pub.journal}}, {{ pub.year}}.
{{ pub.url }}


Included files
--------------

Compressed archives containing results datasets in both tab-separated value and
Excel formats are available for download from {{ site.deploy.publicurl }}.

The line endings for the `.tsv` files are Unix linefeeds. These tab-delimited
files are intended for post-processing in the Unix shell environment with "Unix
toolbox" utilities like `cut`, `sort`, and `awk`.

Excel `.xlsx` files are provided for any other uses.


Contacts
--------

{% for c in pub.contacts -%}
- {{ c.name }} <{{ c.email }}>
{% endfor %}
