// Requires RELAY_URL set in Script Properties (same as test.js)

function createHubstaffProject(projectName, dynamicTask, hours) {
  const payload = { project_name: projectName };

  if (dynamicTask) payload.dynamic_task = dynamicTask;
  if (hours)       payload.hours = hours;

  const result = callDiscordRelay("api/projects", payload);

  if (!result.success) {
    throw new Error("Failed to create Hubstaff project: " + JSON.stringify(result));
  }

  return result.project_id;
}

function deleteHubstaffProject(projectId) {
  const result = callDiscordRelay(`api/projects/${parseInt(projectId)}`, {}, "delete");

  if (!result.success) {
    throw new Error("Failed to delete Hubstaff project: " + JSON.stringify(result));
  }
}

function onHubstaffProjectIdCleared(e) {
  const sheet = e.source.getActiveSheet();
  if (sheet.getName() !== 'Testing') return;

  const range = e.range;
  const row   = range.getRow();
  if (row <= 2) return;
  if (range.getColumn() !== colHubstaffProjectId()) return;

  const newValue = range.getValue();
  const oldValue = e.oldValue;

  if (newValue !== "" || !oldValue || oldValue === "pending") return;

  Logger.log(`Hubstaff Project ID cleared for row ${row}. Deleting project ${oldValue}.`);
  try {
    deleteHubstaffProject(oldValue);
    Logger.log(`Project ${oldValue} deleted successfully.`);
  } catch (err) {
    Logger.log(`Failed to delete project ${oldValue}: ${err.message}`);
  }
}

function onProjectRowAdded(e) {
  const sheet = e.source.getActiveSheet();
  Logger.log(`onProjectRowAdded fired on sheet: "${sheet.getName()}"`);

  if (sheet.getName() !== 'Testing') {
    Logger.log('Sheet name does not match "testing", exiting.');
    return;
  }

  const range = e.range;
  const row   = range.getRow();
  Logger.log(`Edited row: ${row}, col: ${range.getColumn()}`);

  if (row <= 2) {
    Logger.log('Row is header or above, exiting.');
    return;
  }

  const editedCol = range.getColumn();
  if (editedCol !== colMarket() && editedCol !== colCode() && editedCol !== colDateAdded()) {
    Logger.log(`Col ${editedCol} is not a watched column (Market=${colMarket()}, Code=${colCode()}, DateAdded=${colDateAdded()}), exiting.`);
    return;
  }

  const market      = sheet.getRange(row, colMarket()).getValue();
  const code        = sheet.getRange(row, colCode()).getValue();
  const productName = sheet.getRange(row, colProductName()).getValue();
  const dateAdded   = sheet.getRange(row, colDateAdded()).getValue();
  Logger.log(`Row ${row} values — Market: "${market}", Code: "${code}", ProductName: "${productName}", DateAdded: "${dateAdded}"`);

  if (!market || !code || !productName || !dateAdded) {
    Logger.log('One or more required fields are empty, exiting.');
    return;
  }

  const funnelName = sheet.getRange(row, colFunnelName()).getValue();
  Logger.log(`Funnel name: "${funnelName}"`);
  if (!funnelName) {
    Logger.log('Funnel name is empty, exiting.');
    return;
  }

  const lastRow      = sheet.getLastRow();
  const funnelCol    = colFunnelName();
  const hubstaffCol  = colHubstaffProjectId();
  const funnelValues = sheet.getRange(3, funnelCol, lastRow - 2, 1).getValues();
  const projectIds   = sheet.getRange(3, hubstaffCol, lastRow - 2, 1).getValues();

  const alreadyExists = funnelValues.some((r, i) => r[0] === funnelName && projectIds[i][0]);
  if (alreadyExists) {
    Logger.log(`Skipping duplicate: project for "${funnelName}" already exists.`);
    return;
  }

  // Lock the row by writing a placeholder before the API call.
  // Any concurrent trigger firing on this row will see "pending" and skip.
  const projectIdCell = sheet.getRange(row, hubstaffCol);
  projectIdCell.setValue("pending");
  SpreadsheetApp.flush();

  Logger.log(`Creating Hubstaff project for: "${funnelName}"`);
  try {
    const projectId = createHubstaffProject(funnelName);
    projectIdCell.setValue(projectId);
    Logger.log(`Project created successfully. ID: ${projectId}`);
  } catch (err) {
    projectIdCell.setValue(""); // release the lock on failure
    Logger.log(`Hubstaff project creation failed: ${err.message}`);
  }
}

