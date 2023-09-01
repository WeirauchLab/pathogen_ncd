
// FIXME: this is almost worse than hard-coding, but PUBHTMLTABLE will have
// 'public' as part of the pathname when this template is processed
var html = 'data/PUBSHORTNAME.html';
var columnDefs = m4_include(LOCALDATADIR/PUBCOLUMNCONFIG);

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
      Cookies.set('search-help-hidden', 'y', { expires: 30, path: '' });
    } else {
      toggleHelpLink.text(hideHelpText);
      Cookies.remove('search-help-hidden', { path: '' });
    }
  });
});


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

    // add a label (with a tooltip) to each value
    div += '<li><span class="childrow-title" title="' + desc + '">' +
           title + '</span>: ' + value + '</li>';
  });

  div += '</ul></div>';
  return div;
} // formatChild


// fetch the table data with XHR
var jqxhr = $.ajax({ url: html })
  .done(function(data, status, xhr) {
    console.info("Fetched '" + html + "'; HTTP status " + xhr.status);
    table = $(data);
    table.attr('id', 'datatable');          // add 'id="datatable"' attribute
    table.addClass('display verycompact');  // possibly 'nowrap'
    $('#table-viewer').fadeOut();
    $('#table-viewer').html(table).fadeIn();

    // update the 'title' attributes now, before DataTables gets involved
    $('#table-viewer thead th').each(function (i) {
      $(this).attr('title', columnDefs[i].description);
    });

    var dt = $('#datatable').DataTable({
      // no ordering, just the order they appear in the HTML
      order: [], 
      scrollX: false,
      fixedHeader: true,
      //responsive: true,
      //paging: false,
      lengthMenu: [[10, 25, 100, -1], [10, 25, 100, "All"]],
      pageLength: 100,
      columnDefs: columnDefs,
    }); // DataTable init

    // Add event listener for opening and closing details
    // source: https://datatables.net/examples/api/row_details.html
    $('#datatable tbody')
      .on('click', 'td.details-control', function() {
        var tr = $(this).closest('tr');  // the parent <tr>
        var row = dt.row(tr);            // the entire (DataTables) row object

        if (row.child.isShown()) {
          row.child.hide();
          tr.removeClass('shown');
        }
        else {
          row.child(formatChild(row.data())).show();
          tr.addClass('shown');
        }
      });

    // wire up the "Search" button to focus the search box
    var searchBox = $('#datatable_wrapper input[type="search"]');
    var searchButton = $('#search-btn');
    var searchHeader = $('#search');

    // FIXME: animate or highlight somehow
    searchButton.click(function(e) {
      e.preventDefault();
      // just like the anchor would've done
      searchHeader[0].scrollIntoView();
      searchBox.focus();
    });

    // initially hide the pagination controls
    var pageLengthSelect = $('select[name="datatable_length"]');
    var paginateControls = $('#datatable_paginate');
    if (pageLengthSelect.val() === '-1') paginateControls.hide();

    // and if the select box is set to "All"
    pageLengthSelect.change(function(e) {
      if ($(this).val() === '-1') {
        paginateControls.hide();
      } else {
        paginateControls.show();
      }
    });
  }) // done

  .fail(function(data, status, xhr) {
    console.error("Error loading '" + html + "'; HTTP status " +
                  xhr.status + " (" + status + ")");
    alert("Unable to load the data table. Perhaps contact " +
          "the administrator using the link at the bottom of the page?");
  });
