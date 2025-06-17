Supplementary data for Lape, et al. 2025
========================================

What's here:

- `Makefile`
  - described below; run `make` for help
- `git-pre-commit-hook`
  - described below; use this to block Git checkins if metadata present
- `samples.xlsx`
- `supplementary_data_1.xlsx`
- `supplementary_data_2.xlsx`
  - results based on Phecodes; used for the "PHE" tab on the website
- `supplementary_data_3.xlsx`
- `supplementary_data_4.xlsx`
- `supplementary_data_5.xlsx`
- `supplementary_data_6.xlsx`
- `supplementary_data_7.xlsx`
- `supplementary_data_8.xlsx`
  - results based on ICD10 code from UKB data; used for the "ICD10" tab
- `supplementary_data_9.xlsx`
- `supplementary_data_10.xlsx`
- `supplementary_data_legends.pdf`
- `supplementary_info.pdf`

Sanitizing metadata
-------------------

Run `make` for instructions.

If you symlink `git-pre-commit-hook` to `.git/hooks/pre-commit` and make it
executable:

    cd <repo>/.git/hooks
    ln -s ../../supplementary_data/git-pre-commit-hook pre-commit
    chmod a+x pre-commit

…you can have Git check this for you, and prevent you from committing any data
files that contain sensitive metadata.


### Scrubbing metadata from Office file formats

The best option for the time being is to use the built-in facilities of Excel,
Word, and so on for this. They appear to be the most full-featured with the
Windows versions, and may not exist (or may be present only in a limited form)
with the online / Office 365 versions of the Office apps.

An example of this procedure (using Excel) is documented as an SOP on the lab's
wiki.


### Scrubbing metadata from PDF files

The [mat2][] tool is supposed to handle PDFs, but it's intended for use by
journalists to protect their sources, so it's quite aggressive in its methods.

When I attempted to use `mat2` on the PDF in this directory, it resulted in
warnings when processing the PDF with other tools like Ghostscript and [Apache
Tika][tika], so my feeling is it's not worth the gamble. [PDFtk][], however,
appears to remove author and creator information, which is sufficient for our
purposes:

    pdftk in.pdf cat output clean.pdf

Furthermore, mat2 has a complicated dependency chain, including the Meson build
system, various bits of Python, and [GLib], which is not a straightforward
install in our computing environment. PDFtk on the other hand requires only
Java, and a standalone binary is also available.


// Kevin Ernst, 14 Dec 2023; updated Dec 2024

[mat2]: https://0xacab.org/jvoisin/mat2
[tika]: https://tika.apache.org
[pdftk]: https://gitlab.com/pdftk-java/pdftk
[glib]: https://gitlab.gnome.org/GNOME/glib
