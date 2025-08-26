
const chatLog = document.getElementById('chatLog');
const sendBtn = document.getElementById('sendBtn');
const clipInput = document.getElementById('clipInput');

function addMsg(who, text) {
  const div = document.createElement('div');
  div.className = 'msg ' + who;
  div.textContent = text;
  chatLog.appendChild(div);
  chatLog.scrollTop = chatLog.scrollHeight;
}

async function postChatCaption(file) {
  const fd = new FormData();
  fd.append('file', file);
  fd.append('system_prompt', document.getElementById('systemPrompt').value);
  fd.append('num_frames', document.getElementById('numFrames').value);
  fd.append('sampling_type', document.getElementById('samplingType').value);
  fd.append('model', document.getElementById('modelName').value);
  fd.append('prefill', document.getElementById('prefill').value);

  const res = await fetch('/api/chat-caption', { method:'POST', body: fd });
  return await res.json();
}

sendBtn.addEventListener('click', async () => {
  const file = clipInput.files?.[0];
  if (!file) { addMsg('assistant', 'Attach a clip first.'); return; }
  addMsg('user', `Attached: ${file.name}`);
  addMsg('assistant', 'Thinking... extracting frames and querying LM Studio');

  const out = await postChatCaption(file);
  if (out.error) {
    addMsg('assistant', 'Error: ' + out.error);
  } else {
    addMsg('assistant', `[frames used: ${out.frames_used}] ` + out.caption);
  }
});

// ---- Batch ----
const batchBtn = document.getElementById('startBatch');
const batchLog = document.getElementById('batchLog');

function logBatch(line){ batchLog.textContent += line + "\\n"; batchLog.scrollTop = batchLog.scrollHeight; }

let cancelBatch = false;
batchBtn.addEventListener('click', async () => {
  if (!cancelBatch) {
    cancelBatch = true;
    batchBtn.textContent = 'Cancel Batch';
    batchLog.textContent = '';
    const body = {
      target_folder: document.getElementById('targetFolder').value,
      system_prompt: document.getElementById('systemPrompt').value,
      model: document.getElementById('modelName').value,
      prefill: document.getElementById('prefill').value,
      num_frames: Number(document.getElementById('numFrames').value),
      sampling_type: document.getElementById('samplingType').value,
      overwrite: document.getElementById('overwrite').checked,
      prepend_existing: document.getElementById('prependExisting').checked
    };
    try {
      logBatch('Submitting batch job...');
      const res = await fetch('/api/batch-caption', {
        method: 'POST',
        headers: {'Content-Type':'application/json'},
        body: JSON.stringify(body)
      });
      const out = await res.json();
      if (out.error) {
        logBatch('Error: ' + out.error);
      } else {
        logBatch(`Processed ${out.count} files`);
        out.results.forEach(r => {
          if (r.ok) logBatch(`✓ ${r.file} -> ${r.out}`);
          else if (r.skipped) logBatch(`↷ ${r.file} (skipped: ${r.reason})`);
          else logBatch(`✗ ${r.file}: ${r.error}`);
        });
        if (document.getElementById('notifyDone').checked) alert('Batch complete.');
      }
    } catch (e) {
      logBatch('Error: ' + e);
    } finally {
      cancelBatch = false;
      batchBtn.textContent = 'Start Batch Process / Cancel';
    }
  } else {
    cancelBatch = false;
    batchBtn.textContent = 'Start Batch Process / Cancel';
  }
});
