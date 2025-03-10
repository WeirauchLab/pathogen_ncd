The [`{{ data.artifacts.resultsarchive }}`][0] archive contains the ICD10 and
Phecode results seen on the parent page in Excel (<tt>.xlsx</tt>) format. The
`.tar.gz` version is tab-delimited Unix text files with LF [line endings][1].

The [`{{ data.artifacts.supplementarchive }}`][2] archive contains **all
supplemental datasets** from the [_{{ pub.journal }}_ ({{ pub.year }})
publication][3] in Excel format, _including_ the ICD10 and Phecode datasets in
unprocessed form.

## Validating SHA1 checksums

### Windows

* download either or both of the `.zip` archives and
  [`SHA1SUMS`]({{ site.deploy.publicurl }}/data/SHA1SUMS) locally
* open PowerShell in the directory where you downloaded these and run:

    ```powershell
    get-filehash -alg SHA1 *.zip
    ```
* compare these computed hashes with the downloaded `SHA1SUMS`

### macOS

With the default shell:

```bash
shasum -a1 -c <(curl {{ site.deploy.publicurl }}/data/SHA1SUMS)
```

### Linux

Assuming the Bash shell:

```bash
sha1sum --ignore-missing -c <(curl {{ site.deploy.publicurl }}/data/SHA1SUMS)
```

[0]: {{ data.artifacts.resultsarchive }}
[1]: https://en.wikipedia.org/wiki/Newline
[2]: {{ data.artifacts.supplementarchive }}
[3]: {{ pub.url }}
