// ref: https://datatables.net/manual/data/renderers#Custom-helpers
DataTable.render.naSortsLast = function () {
  return function (data, type, row) {
    // custom DataTables renderer that makes sure "n/a"s sort at the bottom
    if (type == 'display') {
      return data;
    } else if (type == 'sort' || type == 'filter') {
      return data == 'n/a' ? -1 : parseFloat(data);
    }
  };
};


// move the scroll position to just above the ICD/PHE tabs
function scrollTabsToTop() {
  // also works, but not sure how to animate it
  //$('#tabs-and-tables')[0].scrollIntoView();
  var tabsTop = $('#tabs-and-tables').offset().top;
  $('html, body').animate({ scrollTop: tabsTop }, 500);
}


// load .tsv with $.ajax and render DataTables table w/ its contents
function loadTab(which, scrollTo = true) {
  var tsv = `data/{{ data.artifacts.basename }}_${which}_Results.tsv`;
  var tableDiv = $('#table-' + which.toLowerCase());
  var columnDefs = {
{%- for ds in data.datasources %}
    '{{ ds }}': {{ data.datasources[ds].columns }},
{%- endfor %}
  };
  var columnDefs = columnDefs[which];

  // apply custom renderers
  for (i = 0; i < columnDefs.length; i++) {
    if (columnDefs[i].renderer) {
      columnDefs[i].render = DataTable.render[columnDefs[i].renderer]();
    }
  }

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
              { buttons: [
                  { extend: 'copy', text: 'Copy' },
                  { extend: 'csv', text: 'Download CSV' },
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
      }); // DataTable init

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
