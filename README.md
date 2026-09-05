# Insurgency: Sandstorm Mod Tools - Plugin Module Fix

Fixes the **Missing Modules** error that stops most stock Unreal plugins from being enabled in the Insurgency: Sandstorm Mod Tools editor. Present since **mod tools update 1.17**.

Two double-clickable `.bat` files.

---

## The error

Enable a stock plugin — Movie Render Queue, for example — and the editor refuses to load it:

> **Missing Modules**
>
> The following modules are missing or built with a different engine version:
>
> ```
> MovieRenderPipelineCore
> MovieRenderPipelineSettings
> MovieRenderPipelineRenderPasses
> MovieRenderPipelineEditor
> (+368 others, see log for details)
> ```
>
> Engine models modules cannot be compiled at runtime please build through your IDE.

Building through an IDE is not an option: the mod tools ship without the source needed to compile any of this.

## The cause

Nothing is actually missing. Every plugin folder in `SandstormEditor\Engine\Plugins` contains a small text file, `UE4Editor.modules`, listing the DLLs that plugin provides and stamped with a `BuildId` identifying the build that produced them:

```json
{
	"BuildId": "b4cb3d11-9630-4bc7-9513-1c514721e7bc",
	"Modules":
	{
		"MovieRenderPipelineCore": "UE4Editor-MovieRenderPipelineCore.dll"
	}
}
```

The editor compares that stamp against its own in `SandstormEditor\Engine\Binaries\Win64\UE4Editor.modules`. If they differ it discards the entire manifest and never looks at the DLLs sitting beside it so it reports those modules as missing and causes the mod tools to crash.

The editor and its plugins were likely built in two separate passes, leaving two different `BuildId` values on disk and since update 1.17 install the majority of plugin manifests carry the wrong one.

## The fix

Rewrite the `BuildId` in the mismatched manifests to the editor's own value. 36 bytes change per file; size, encoding and line endings stay identical.

| Modified | Never read or written |
| --- | --- |
| `Engine\Plugins\**\UE4Editor.modules` | Every `.dll`, `.exe`, `.pdb` |
| | Project assets, maps, Blueprints |
| | `Insurgency.uproject`, all `Config\` |
| | Engine binaries and content |

The target `BuildId` is **read from your own editor at runtime** — no GUID is hardcoded, so this stays correct across different mod tools builds. The value being replaced is read from each file individually, and any manifest whose `BuildId` isn't the same length is skipped rather than rewritten.

## Usage

1. Download both `.bat` files ([latest release](../../releases/latest)).
2. Put them in the **root of your Sandstorm Editor folder** — the one containing `Engine` and `Insurgency`:

   ```
   ...\SandstormEditor\
   ├─ Engine\
   ├─ Insurgency\
   ├─ FixSandstormPlugins.bat        <- here
   └─ RestoreSandstormPlugins.bat    <- and here
   ```

3. **Close the Unreal Editor completely.** (The script refuses to run while it's open.)
4. Double-click **`FixSandstormPlugins.bat`**.

It reports what it found, then asks two questions:

- **Back up the plugin manifests?** — copies all the `UE4Editor.modules` files to `SandstormEditor\PluginManifestBackup\`. Say **Y**. If a backup already exists it keeps it rather than overwriting, so your undo is never lost.
- **Apply the fix?** — rewrites the mismatched build IDs, then re-reads every file from disk and prints a before/after comparison.

A successful run ends with:

```
    BuildId                                Manifests  Status
    88689677-daf8-4e1e-956b-78883c571b54         372  MATCHES EDITOR

    RESULT: PASS - every plugin manifest now matches the editor.
```

5. Launch the editor, open **Edit → Plugins**, enable what you need, and restart when prompted.

### Undoing it

Double-click **`RestoreSandstormPlugins.bat`**. It shows the build IDs held in your backup alongside the editor's, confirms, copies the originals back, and prints the same before/after verification.

## Notes

- **This does not add compile support.** It only unlocks plugins whose binaries already exist on disk. The mod tools ship without the Editor and Developer source trees.
- **A mod tools update may undo it.** If NWI replaces the manifests, the error returns so run the fix again.
- Both `.bat` files are plain text; the whole PowerShell script is embedded and readable in Notepad. Nothing is downloaded at runtime.

More information about issues with the Insurgency: Sandstorm - Mod Tools & Editor can be found here:
https://mod.io/g/insurgencysandstorm/r/sandstorm-editor-mod-tools-common-issues-troubleshooting-guide

## Requirements
- Windows 10/11 with PowerShell 5.1 and above
- Insurgency: Sandstorm - Mod Tools & Editor: https://store.epicgames.com/p/insurgency-sandstorm--mod-tools
