// Paste into the sheet: Extensions > Apps Script. Appends posted CSV rows to Test Log.
function doPost(e) {
  try {
    var sheet = SpreadsheetApp.getActive().getSheetByName('Test Log');
    if (!sheet) throw new Error('no tab named "Test Log"');
    var rows = Utilities.parseCsv(e.postData.contents).slice(1);   // drop CSV header
    rows.forEach(function (r) {
      if (r.length !== 12) throw new Error('expected 12 columns, got ' + r.length);
    });
    rows.forEach(function (r) { sheet.appendRow(r); });
    return ContentService.createTextOutput('added ' + rows.length + ' row(s)');
  } catch (err) {
    return ContentService.createTextOutput('ERROR: ' + err.message);
  }
}
