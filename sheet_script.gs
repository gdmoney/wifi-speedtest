// Paste into the sheet: Extensions > Apps Script. Appends posted CSV rows to Test Log.
function doPost(e) {
  var rows = Utilities.parseCsv(e.postData.contents).slice(1);   // drop CSV header
  var sheet = SpreadsheetApp.getActive().getSheetByName('Test Log');
  rows.forEach(function (r) { sheet.appendRow(r); });
  return ContentService.createTextOutput('added ' + rows.length + ' row(s)');
}
