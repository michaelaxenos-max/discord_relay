// Store RELAY_URL in Script Properties:
// Extensions > Apps Script > Project Settings > Script Properties
// Key: RELAY_URL  Value: https://your-app.fly.dev

function getColumnByName(sheetName, columnName, headerRow = 1) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  const headers = sheet.getRange(headerRow, 1, 1, sheet.getLastColumn()).getValues()[0];
  const col = headers.findIndex(h => h === columnName) + 1;
  if (col === 0) throw new Error(`Column "${columnName}" not found in sheet "${sheetName}"`);
  return col;
}

function createForumPost(channelId, title, content = null, tag = null) {
  const payload = {
    channel_id: channelId,
    title: title,
    content: content,
  };

  if (tag) {
    payload.tags = [tag];
  }

  const result = callDiscordRelay("discord/forum/post", payload);

  if (!result.ok) {
    throw new Error("Failed to create forum post: " + JSON.stringify(result));
  }

  return result.thread_id;
}

function updateForumPost(channelId, threadId, tag = null, comment = null, title = null) {
  const payload = {
    channel_id: channelId,
    thread_id: threadId,
  };

  if (tag) {
    payload.tags = [tag];
  }

  if (comment) {
    payload.content = comment;
  }

  if (title) {
    payload.title = title;
  }

  const result = callDiscordRelay("discord/forum/update", payload);

  if (!result.ok) {
    throw new Error("Failed to update forum post: " + JSON.stringify(result));
  }

  return result;
}

function deleteForumPost(threadId) {
  const result = callDiscordRelay("discord/forum/delete", { thread_id: threadId }, "delete");

  if (!result.ok) {
    throw new Error("Failed to delete forum post: " + JSON.stringify(result));
  }

  return result;
}

function callDiscordRelay(endpoint, payload, method = "post") {
  const relayUrl = PropertiesService.getScriptProperties().getProperty("RELAY_URL");

  const options = {
    method: method,
    contentType: "application/json",
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  };

  const response = UrlFetchApp.fetch(relayUrl + "/" + endpoint, options);
  return JSON.parse(response.getContentText());
}


// ── Hubstaff: add Juliet (4267161) to editor tasks on project 4027729 ────────
// Task IDs for editor tasks on project 4027729:
//   162859540 Deep Research GPT
//   162859542 Image (AI regen)
//   162859543 Image (from scratch)
//   162859546 Video - 2min
//   162859547 Video – 3 min
//   162859548 Video – 4 min
//   162859549 Video – 5 min
//   162859550 Video – 6 min
//   162859551 Video – 7 min
//   162859552 Video – Script change
//   162859554 Video – Scrollstopper
//   162859556 Video – under 1 min
//
// Current assignees on each task: [2196094, 3517608, 4262600, 4264322]
// Want to add Juliet: 4267161
//
// The PUT request we make:
//   PUT https://api.hubstaff.com/v2/tasks/{task_id}
//   Authorization: Bearer {access_token}
//   Content-Type: application/json
//   Body: {
//     "assignee_ids": [2196094, 3517608, 4262600, 4264322, 4267161],
//     "lock_version": <current lock_version from GET /v2/tasks/{task_id}>,
//     "summary": "Video – 3 min",
//     "status": "active"
//   }
//
// Response: 403 {"code":"not_authorized","error_code":10003,"error":"Can not update a task for this user in this project"}
//
// To test manually with curl (replace ACCESS_TOKEN and pick any task_id):
//
// Step 1 – get current lock_version:
//   curl -H "Authorization: Bearer ACCESS_TOKEN" https://api.hubstaff.com/v2/tasks/162859547
//
// Step 2 – update assignees:
//   curl -X PUT https://api.hubstaff.com/v2/tasks/162859547 \
//     -H "Authorization: Bearer ACCESS_TOKEN" \
//     -H "Content-Type: application/json" \
//     -d '{"assignee_ids":[2196094,3517608,4262600,4264322,4267161],"lock_version":1,"summary":"Video – 3 min","status":"active"}'

/// here below this
//
//
//
  // ── Column Q changed (status updated) ─────────────────────────────────
  if (col === 17) {
    if (threadId){
      let comment = null;
      if (status === "For proofreading") {
        const builtFunnel = sheet.getRange(row, 18).getValue();
        if (!builtFunnel) {
          sheet.getRange(row, 17).setValue(e.oldValue || "");
          SpreadsheetApp.getUi().alert("Please add the funnel link in column R before moving to For proofreading.");
          return;
        }
        const competitorFunnel = sheet.getRange(row, 8).getValue();
        comment = `This funnel is ready for proofreading.\n\nFunnel to review: ${builtFunnel}\nCompetitor reference: ${competitorFunnel}`;
      }
      updateForumPost(channelId, threadId, status, comment);
    };
  }
}




  function getDiscordMention(name, team) {
    const isFunnelBuilder = team == 'Funnel Builder';
    const nameHeader = isFunnelBuilder ? 'Funnel Builder' : 'Editor';
    const idHeader   = isFunnelBuilder ? 'Discord Id Funnel Builders' : 'Discord Id Editors';

    const nameCol = getColumnByName(nameHeader, "Assignment", 1);
    const idCol   = getColumnByName(idHeader, "Assignment", 1);

    const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName("Assignment");
    const names = sheet.getRange(1, nameCol, sheet.getLastRow(), 1).getValues();
    const row = names.findIndex(r => r[0] === name);
    if (row === -1) return "";

    const userId = sheet.getRange(row + 1, idCol).getValue();
    return "<@" + userId + ">";
  }
