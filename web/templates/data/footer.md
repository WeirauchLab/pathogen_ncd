The [`{{ data.artifacts.resultsarchive }}`][0] archive contains the ICD10 and
Phecode results seen on the parent page in Excel (`.xlsx`) format. The
[`.tar.gz` version][1] is tab-delimited Unix text files with LF [line endings][2].

The [`{{ data.artifacts.supplementarchive }}`][3] archive contains **all
supplemental datasets** from the [_{{ pub.journal }}_ ({{ pub.year }})
publication][4] in Excel format, _including_ the ICD10 and Phecode datasets in
unprocessed form.

## Verifying download integrity

The [`SHA1SUMS`]({{ site.deploy.publicurl }}/data/SHA1SUMS) file provided here
contains cryptographic checksums for verifying that the downloaded archives
have not been corrupted. See [this GitHub gist][5] for more information.

### Windows

* download either or both of the `.zip` archives and
  `SHA1SUMS` locally
* open PowerShell in the directory where you downloaded these and run:

    ```powershell
    get-filehash -alg SHA1 *.zip | foreach {
        echo $($_.hash.tolower() + "  " + $(resolve-path -relative $_.path))
    }
    ```
* compare the output of the above command with the downloaded `SHA1SUMS`

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
[1]: {{ data.artifacts.resultstarball }}
[2]: https://en.wikipedia.org/wiki/Newline
[3]: {{ data.artifacts.supplementarchive }}
[4]: {{ pub.url }}
[5]: https://gist.github.com/ernstki/94a7d14b998d1504d4117b7a0b5331a0
