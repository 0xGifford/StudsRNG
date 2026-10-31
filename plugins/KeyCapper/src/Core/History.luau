--!strict
-- Single responsibility: group a set of Workspace mutations into ONE undo
-- entry. Without this, a held-brush stroke would push one waypoint per key and
-- the user would have to Ctrl+Z a hundred times to undo one drag.
--
-- Recording can legitimately fail (another recording already open, Studio
-- busy): callers must stay correct with a nil id, hence the nil-tolerant API.

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local History = {}

export type Recording = string?

function History.Begin(name: string): Recording
	return ChangeHistoryService:TryBeginRecording(name, name)
end

function History.Commit(recording: Recording)
	if not recording then return end
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end

-- For a stroke that ended up placing nothing: leaves no undo entry behind.
function History.Cancel(recording: Recording)
	if not recording then return end
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
end

return History
