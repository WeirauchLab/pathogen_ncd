// wire up tooltips for all of the affiliations
var affil;

$('#authors sup a')
  .click(function(e) {
    e.preventDefault();
  })
  .mouseover(function() {
    // get associated a.footnote > span
    affil = $($(this).attr('href'));
    affil.addClass('highlight');
  })
  .mouseout(function() {
    affil = $($(this).attr('href'));
    affil.removeClass('highlight');
  });


// wire up the "Hide this help" link
var toggleHelpContainer = $('#search-help-toggle-cont');
var toggleHelpLink = $('#search-help-toggle');
var searchHelp = $('#search-help');
var showHelpText = 'Show search help';
var hideHelpText = 'Hide this help';

// if user hasn't hidden the search help on their last visit
if (Cookies.get('search-help-hidden')) {
  toggleHelpLink.text(showHelpText);
} else {
  toggleHelpLink.text(hideHelpText);
  searchHelp.show();
}

// now that the link text is updated, show the show/hide link
toggleHelpContainer.show();

toggleHelpLink.on('click', function(e) {
  e.preventDefault();
  searchHelp.animate({
    opacity: 'toggle',
    height: 'toggle'
  }, function() {
    if (searchHelp.is(':hidden')) {
      toggleHelpLink.text(showHelpText);
      // https://github.com/js-cookie/js-cookie#basic-usage
      Cookies.set('search-help-hidden', 'y', { expires: 400, path: '' });
    } else {
      toggleHelpLink.text(hideHelpText);
      Cookies.remove('search-help-hidden', { path: '' });
    }
  });
});


// wire up the "ICD10" and "Phecode" tabs
// the string arguments to 'loadTab' correspond to the names of the
// columns.json keys and data/pathogen_ncd-{ICD,PHE}.tsv files
{% for ds in data.datasources -%}
$('#tab-{{ data.datasources[ds].tabname | lower }}')
  .on('click', e => loadTab('{{ data.datasources[ds].tabname }}'));
{% endfor %}

// load the default tab, but don't scroll to it
{% set defaulttab = data.datasources | sort(attribute='order') | first -%}
loadTab('{{ defaulttab }}', false);

// formatter for the child rows (expanded details)
function formatChild(rowdata) {
  var div = '<div class="childrow"><ul>';

  columnDefs.forEach(function(cdef) {
    if (cdef.visible !== false) return;  // skip the visible ones

    var colidx = cdef.targets;           // the column index
    if (colidx < 2) return;              // skip details and rowid
    var title = columnDefs[colidx].title || columnDefs[colidx].name;
    var desc = columnDefs[colidx].description;

    // set a default for empty rows
    var value = rowdata[colidx] || '<span class="muted">empty</span>';

    // split comma-delimited values so they wrap properly
    value = value.replace(/,(\w)/g, ', $1');

    // make everything that looks like a PMID into a link
    value = value.replace(
      /(\d{6,})(\.0)?/g,
      '<a title="Open PubMed record for PMID $1 (in current window/tab)" ' +
      'href="https://www.ncbi.nlm.nih.gov/pubmed/?term=$1">$1</a>'
    );

    // make everything that looks like a UniProt name into a link
    value = value.replace(
      /([A-Z][A-Z0-9_]{5,})/g,
      '<a title="Open UniProtKB record for \'$1\' (in current window/tab)" ' +
      'href="https://www.uniprot.org/uniprot/$1">$1</a>'
    );

    // add <abbr> tags for Direct/Inferred/No evidence
    value = value.replace(
      /\b(D)(?=\()/g, '<abbr title="Direct evidence">$1</abbr>'
    ).replace(
      /\b(I)(?=\()/g,
      '<abbr title="Inferred evidence; e.g., experiment assayed ' +
      'orthologous protein">$1</abbr>'
    ).replace(
      /^(N)$/g, '<abbr title="No available evidence">$1</abbr>'
    );

    // add a label (with a tooltip) to each value
    div += '<li><span class="childrow-title" title="' + desc + '">' +
           title + '</span>: ' + value + '</li>';
  });

  div += '</ul></div>';
  return div;
} // formatChild


function doDetailsControlOnClick() {
  // Add event listener for opening and closing details (not currently used)
  // source: https://datatables.net/examples/api/row_details.html
  $('#datatable tbody')
    .on('click', 'td.details-control', function() {
      var tr = $(this).closest('tr');  // the parent <tr>
      var row = dt.row(tr);            // the entire (DataTables) row object

      if (row.child.isShown()) {
        row.child.hide();
        tr.removeClass('shown');
      } else {
        row.child(formatChild(row.data())).show();
        tr.addClass('shown');
      }
    });
} // doDetailsControlOnClick


function scrollTabsToTop() {
  // also works, but not sure how to animate it
  //$('#tabs-and-tables')[0].scrollIntoView();
  var tabsTop = $('#tabs-and-tables').offset().top;
  $('html, body').animate({ scrollTop: tabsTop }, 500);
}

function loadTab(which, scrollTo = true) {
  var tsv = `data/{{ data.artifacts.basename }}_${which}_Results.tsv`;
  var tableDiv = $('#table-' + which.toLowerCase());
  var columnDefs = {
{%- for ds in data.datasources %}
      "{{ ds }}": {{ data.datasources[ds].columns }},
{%- endfor %}
  };
  var columnDefs = columnDefs[which];
  var loadingMsg = $('#table-viewer .loading');

  $('#table-viewer').children().hide();

  // don't re-download if already loaded
  if (tableDiv.hasClass('loaded')) {
    tableDiv.show();
    scrollTabsToTop();
    return;
  }

  loadingMsg.show();

  // start: fetch the table data with XHR
  var jqxhr = $.ajax({ url: tsv })
    .done(function(data, status, xhr) {
      console.info("Fetched '" + tsv + "'; HTTP status " + xhr.status);
      var table = $('<table>');
      var tableID = 'datatable-' + which.toLowerCase();
      table.attr('id', tableID);
        table.addClass('display verycompact');  // & possibly 'nowrap'

        tableDiv.fadeOut();
        loadingMsg.hide()
        tableDiv.append(table);
        tableDiv.addClass('loaded');
        tableDiv.fadeIn();

        // break up the .tsv file into an array, discarding the header row, and
        // the final, empty element (since Unix text files are newline-delimited)
        var data = data.split(/\n/).slice(1).filter(e => e.length);
        // now, split on tab characters to make a two-dimensional array
        data = data.map(e => e.split(/\t/));

        var dt = table.DataTable({
          data: data,
          columnDefs: columnDefs,
          order: {{ data.ordering | tojson }},
          layout: {
              //topStart: [ 'pageLength', { buttons: ['colvis'] } ],
              topEnd: [
                  { buttons:
                    [
                      { extend: 'copy', text: 'Copy' },
                      { extend: 'csv', text: 'Download CSV' }
                    ]
                  },
                  'search',
              ],
          },
          scrollX: false,
          lengthMenu: [[10, 25, 100, 500, -1], [10, 25, 100, 500, "All"]],
          pageLength: 100,
          // disabled for now; doesn't work with the tabs
          //fixedHeader: true,
          // https://datatables.net/reference/option/deferRender
          deferRender: true,
          // https://datatables.net/examples/advanced_init/row_callback.html
          // better to do stuff like this in lib/transform.py, but here's how…
          //createdRow: (r, d, i) => {
          //  // debugging:
          //  //for (let i = 0; i < d.length; i++) {
          //  //  console.log(`data cell d[${i}] (${d[i]}) is ${r.querySelector(`:nth-child(${i+1})`).textContent}`);
          //  //}
          //  //if (d[6] == "") r.querySelector(':nth-child(7)').textContent = 'n/a';
          //  //if (d[8] == "") r.querySelector(':nth-child(9)').textContent = 'n/a';
          //},
      }); // DataTable init

      // onclick handler for opening and closing details (not currently used)
      //doDetailsControlOnClick();

      // tooltips for DataTables Buttons extension (until I find a better way)
      $('button.dt-button.buttons-copy').attr(
          'title', "Copy table data to the system clipboard "
                 + "(all pages, ignoring search/filters)");
      $('button.dt-button.buttons-csv').attr(
          'title', "Download table data as a comma-separated value (.csv) file");

      // add tooltips for column headers; arrow functions don't have a 'this'!
      // ref: https://old.reddit.com/r/javascript/comments/nqrmuu/askjs_why_are_arrow_functions_used_so_universally/h0ct1xb
      table.find('thead th').each(function(i) {
        $(this).attr('title', columnDefs[i].description);
      });

      // wire up the "Search" button to focus the search box
      var searchBox = $('#' + tableID + '_wrapper input[type="search"]');
      var searchLink = $('#search-link');
      var searchHeader = $('#search');

      searchLink.click(function(e) {
        e.preventDefault();
        // just like the anchor would've done
        searchHeader[0].scrollIntoView();
        searchBox.focus();
      });

      // initially hide the pagination controls
      var pageLengthSelect = $('select[name="datatable_length"]');
      var paginateControls = $('#' + tableID + '_paginate');
      if (pageLengthSelect.val() === '-1') paginateControls.hide();

      // and if the select box is set to "All"
      pageLengthSelect.change(function(e) {
        if ($(this).val() === '-1') {
          paginateControls.hide();
        } else {
          paginateControls.show();
        }
      });

      // finally, scroll so the tab strip is at the top of the viewport
      if (scrollTo) scrollTabsToTop();
    }) // done

    .fail(function(data, status, xhr) {
      console.error("Error loading '" + tsv + "'; HTTP status " +
                    xhr.status + " (" + status + ")");
      alert("Unable to load the data table. Perhaps contact " +
            "the administrator using the link at the bottom of the page?");
    });
} // loadTab(which)
