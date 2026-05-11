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

function createForumPost(channelId, title, content, tag) {
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

function updateForumPost(channelId, threadId, tag, comment) {
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
