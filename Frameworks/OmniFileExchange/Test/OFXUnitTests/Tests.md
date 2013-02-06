## Tests left to write

### editing
* add two documents quickly
* update an existing document
* update an existing document while the previous upload is still going on
* remove an existing document
* remove an existing document while an upload of a previous edit is still going on
* rename existing document
* rename existing document while upload of previous edit is still going on
* edit document while agent isn't running (on Mac the user could edit files directly)

### syncing
* add/edit document on A, launch B and make sure it downloads
* add/edit document on A while B is running, wait for timer and make sure it downloads
* delete document on A, launch B and make sure it downloads
* delete document on A while B is running, wait for timer and make sure it disappears
* list files on B before they've downloaded
* request download of a non-downloaded file
* try opening a non-downloaded file (make the stubs chmod 0 and maybe relinquish-to-reader auto-start a download?)

### conflicts
* add document on A and B with network off, sync and make sure something reasonable happens (either need to merge or rename one document automatically)
* edit existing document on A and B with network off (add flag to simulate network missing), enable network and make sure conflict is produced
* edit document on A, delete on B
* generate a 3 or 4 way conflict
* resolve conflicts
* rename to two different names on two different devices

### metadata
* upload/download a large-ish document and make sure the progress advances

### mac agent
* quickly running otest twice will fire up two agents on the same directory (Xcode isn't quite making sure the old one is dead somehow??) The Mac agent should really lock the local account directories to prevent two copies of itself from provoking catastrophic corruption.

### Offline/Pause
* do add/move/delete/edit while the agent isn't running (need pause support for Mac agent anyway).
