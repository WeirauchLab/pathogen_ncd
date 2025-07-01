{{ pub.title }}
==============================================================================

{{ pub.author.surname }} et al., {{ pub.journal}} {{ pub.issue }} ({{ pub.year}}).
{{ pub.url }}

These files were obtained from:

    {{ site.deploy.publicurl }}


Verifying download integrity
----------------------------

The `SHA1SUMS` file obtained from the above URL may be employed to verify that
the archives have not been corrupted; further instructions may be found at the
web site. Briefly:

    # Linux, assuming Bash or Z shell
    sha1sum --ignore-missing -c <(curl {{ site.deploy.publicurl }}/data/SHA1SUMS)

    # macOS
    shasum -a1 -c <(curl {{ site.deploy.publicurl }}/data/SHA1SUMS)


Contacts
--------

{% for c in pub.contacts -%}
- {{ c.name }} <{{ c.email }}>
{% endfor %}
