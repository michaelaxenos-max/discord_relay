
function checklist(e) { 
                                            
  if (!e || !e.range) return;                                             
                                                                          
  const sheet = e.range.getSheet();                                       
  if (sheet.getName() !== "Testing") return;                              
                                                                          
  const row = e.range.getRow();                                           
  const col = e.range.getColumn();
                                                                          
  // Only care about column Q (17)                                        
  if (col !== 17 || row < 2) return;
                                                                          
  const newValue = e.range.getValue();                                    
  if (newValue !== "For proofreading") return;
                                                                          
  const checklistLink = sheet.getRange(row, 16).getValue(); // Column P   
  const checkFunnelLink = sheet.getRange(row, 18).getValue(); // Column R  
  if (checklistLink.toString().trim() == "") {
        // Block it — set to "ADD CHECKLIST FIRST"                              
    e.range.setValue("ADD CHECKLIST FIRST");
    Logger.log('event range: '+ e.range)
    SpreadsheetApp.getUi().alert(                                           
      "⚠️ Add checklist first!\n\nPlease add the Self QA Checklist in column P before moving to For Proofreading"                                    
    );
  };                                                              
              
  if (checkFunnelLink.toString().trim() == "") {    
    e.range.setValue("In progress");                         
    SpreadsheetApp.getUi().alert(                                           
      "⚠️ Add Funnel link first!\n\nPlease add the Funnel Link in column R before moving to For Proofreading"                                    
    );
  };
}

function trackFunnelAssignment(e) {
  console.log('calling the sheet');
  if (!e || !e.range) return;

  const sheet = e.range.getSheet();
  if (sheet.getName() !== "Testing") return;

  const row = e.range.getRow();
  const col = e.range.getColumn();
  if (row < 2) return;

  const nameCol = getColumnByName('Funnel Builder');
  const funnelCol = getColumnByName('Funnel Name');
  const statusCol = getColumnByName('Funnel Editing Status');
  const postCol = colFunnelPostId();
  const name    = sheet.getRange(row, nameCol).getValue().toString().trim(); // Col M
  
  const funnel = sheet.getRange(row, funnelCol).getValue();       // K                        
  const status  = sheet.getRange(row, statusCol).getValue().toString().trim(); // Col Q
  const props = PropertiesService.getScriptProperties();
  const channelId = props.getProperty('DISCORD_FUNNEL_CHANNEL_ID');
  let postId = sheet.getRange(row, postCol).getValue();

  // ── Column M changed (name assigned) ──────────────────────────────────
  if (col === nameCol) {
    if (name === "") {
      if (postId) {
        deleteForumPost(postId);
        sheet.getRange(row, postCol).setValue('');
      };
      return;
    }
    const title = `${funnel} - ${name}`;
    const mention = getDiscordMention(name, 'Funnel Builder');
    const content = `${mention} claimed this funnel.`;
    postId = createForumPost(channelId, title, content, status);                                       

    sheet.getRange(row, postCol).setValue(postId);
    return;
  }

  // ── Column Q changed (status updated) ─────────────────────────────────
  console.log('statusCol = ', statusCol);
  console.log('statusCol = ', col);
  if (col === statusCol) {
    if (status === "In progress") {
      const dateCell = sheet.getRange(row, colDateStarted());
      if (dateCell.getValue() === "") {
        dateCell.setValue(formatDate(new Date()));
      }

    }

    // C ol U (21) — date when set to "Ready"
    if (status === "Ready") {
      const dateCell = sheet.getRange(row, colDateCompleted());
      if (dateCell.getValue() === "") {
        dateCell.setValue(formatDate(new Date()));
      }
    }

    console.log('postID = ', postId);
    if (postId){
      let comment = null;
      console.log('status = ', status); 
      if (status === "For proofreading") {
        const builtFunnel = sheet.getRange(row, colFunnelishLink()).getValue();
        if (!builtFunnel) {
          sheet.getRange(row, colFunnelEditingStatus()).setValue(e.oldValue || "");
          SpreadsheetApp.getUi().alert("Please add the funnel link in column R before moving to For proofreading.");
          return;
        }
        const competitorFunnel = sheet.getRange(row, colCompetitorFunnel()).getValue();
        comment = `This funnel is ready for proofreading.\n\nFunnel to review: ${builtFunnel}\nCompetitor reference: ${competitorFunnel}`;
      }
      console.log('updateForumPost');
      updateForumPost(channelId, postId, status, comment);
    };
  };
};

function trackEditingAssignment(e) {
  if (!e || !e.range) return;

  const sheet = e.range.getSheet();
  if (sheet.getName() !== "Testing") return;

  const row = e.range.getRow();
  const col = e.range.getColumn();
  if (row < 2) return;

  const postCol = colEditingPostId();
  const nameCol = colEditor()
  const name    = sheet.getRange(row, nameCol).getValue().toString().trim(); // Col M
  
  const gDriveName = sheet.getRange(row, colGdriveFolderName()).getValue();       // K                        
  const status  = sheet.getRange(row, colAdsStatus()).getValue().toString().trim(); // Col Q
  const props = PropertiesService.getScriptProperties();
  const channelId = props.getProperty('DISCORD_TESTING_FORUM_ID');
  let postId = sheet.getRange(row, postCol).getValue();

  // ── Column M changed (name assigned) ──────────────────────────────────
  if (col === nameCol) {
    if (name === "") {
      if (postId) {
        deleteForumPost(postId);
        sheet.getRange(row, postCol).setValue('');
      };
      return;
    } else {
      if (postId) {
        const mention = getDiscordMention(name, 'Editor');
        const comment = `${mention} is now assigned to ${gDriveName}`;
        updateForumPost(channelId, postId, status, comment);
      };
      return;
    }
  }

  if (col == colProductName()) {
    const title = `${gDriveName}`;
    postId = createForumPost(channelId, title, null, status);                                       

    sheet.getRange(row, postCol).setValue(postId);
    return;
  }

  // ── Column Q changed (status updated) ─────────────────────────────────
  if (col === colAdsStatus()) {
    if (postId){
      let comment = null;
      updateForumPost(channelId, postId, status, comment);
    };
  };
};

function clearFunnelDatabase() {                                                           
  PropertiesService.getScriptProperties().deleteProperty("funnels_assigned");             
  Logger.log("Database cleared.");                                                         
}


function getColumnByName(columnName, sheetName = 'Testing', headerRow = 2) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  const headers = sheet.getRange(headerRow, 1, 1, sheet.getLastColumn()).getValues()[0];
  const col = headers.findIndex(h => h === columnName) + 1;
  if (col === 0) throw new Error(`Column "${columnName}" not found in sheet "${sheetName}"`);
  return col;
}

// post creation is when product is added and trigger on column b selection.
// Post message when someone assigns themself
// Update status automatically
