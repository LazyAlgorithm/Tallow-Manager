using System;
using System.IO;
using Tessera;

namespace TesseraHub;

/// Standalone manager controller. Uses the same UI runtime and artwork as Hub.
[Component]
class EngineManagerUi : Component
{
	UIDocument mDocument;
	UIElement mInstalled, mAvailable, mTemplate, mDialog;
	Release mRelease ~ delete _;
	Task mTask ~ delete _;
	String mError = new .() ~ delete _;
	String mInstallPath = new .() ~ delete _;
	bool mChecking;
	bool mReady;

	public override void Start()
	{
		mInstallPath.Set(Machine.ToolsFolder);
		mInstallPath.Append("/../engines");
		Library.Load();
	}

	UIElement Find(StringView id) => mDocument.Find(id);

	public override void Update()
	{
		if (mDocument == null)
		{
			mDocument = GetComponent<UIDocument>();
			if (mDocument == null || mDocument.Data == null || mDocument.Data.root == null) return;
			mInstalled = Find("installedversions");
			mAvailable = Find("availableversions");
			mTemplate = Find("entrytemplate");
			mDialog = Find("dialog");
			mDialog.visible = false;
			Find("settings").visible = false;
			Find("folderpath").SetText(mInstallPath);
			Find("progress").visible = false;
			Find("message").visible = false;
			Find("launchbutton").visible = false;
			Find("removebutton").visible = false;
			Find("folderbutton").visible = false;
			Find("primary").SetText("CHECK FOR RELEASES");
			Find("summary").SetText("Install Tallow engine builds side by side. No Python required to download an engine.");
			mReady = true;
			CheckReleases();
		}
		if (mTask != null)
		{
			Find("progress").visible = !mTask.Finished;
			let status = scope String();
			mTask.GetStatus(status);
			Find("progresstext").SetText(status);
			if (mTask.Fraction >= 0) Find("progressbar").value = mTask.Fraction;
			if (mTask.Finished)
			{
				let success = mTask.Succeeded;
				mError.Clear();
				if (!success) mTask.GetError(mError);
				Find("message").visible = true;
				Find("message").SetText(success ? "Engine installed successfully." : mError);
				Find("message").SetClass("messageok", success);
				delete mTask;
				mTask = null;
				Find("progress").visible = false;
			}
		}
	}

	void CheckReleases()
	{
		let item = Library.Catalog.FindItem("tessera");
		if (item == null) return;
		let release = new Release();
		let error = scope String();
		if (!Releases.Latest(item, true, release, error))
		{
			delete release;
			Find("message").visible = true;
			Find("message").SetText(error);
			return;
		}
		DeleteAndNullify!(mRelease);
		mRelease = release;
		Find("title").SetText(scope $"Tallow {release.tag}");
		Find("factversion").SetText(release.tag);
		Find("factbuild").SetText("Verified during installation");
		Find("notes").SetText(release.notes);
		Find("primary").SetText("INSTALL VERSION");
		let entry = mTemplate.Clone();
		entry.attributes.Remove("id");
		entry.parent = mAvailable;
		mAvailable.children.Add(entry);
		for (let child in entry.children)
		{
			if (!child.HasClass("entrytext")) continue;
			for (let label in child.children)
			{
				if (label.HasClass("entryname")) label.SetText(release.tag);
				if (label.HasClass("entrystate")) label.SetText("Available");
			}
		}
	}

	void OnInstall()
	{
		if (mTask != null) return;
		if (mRelease == null)
		{
			Find("message").visible = true;
			Find("message").SetText("Release discovery is not yet connected. No files were changed.");
			return;
		}
		mDialog.visible = true;
		Find("dialogtext").SetText(scope $"Install {mRelease.tag}? This will not replace other engine versions.");
	}

	void OnDialogConfirm()
	{
		mDialog.visible = false;
		if (mRelease == null || mTask != null) return;
		let selected = new Release();
		mRelease.CopyTo(selected);
		let root = new String(mInstallPath);
#if BF_PLATFORM_WINDOWS
		let asset = new String("Tessera-Windows.zip");
#else
		let asset = new String("Tessera-Linux.zip");
#endif
		mTask = new Task("Installing Tallow", "engine", new [=](task) =>
			{
				defer { delete selected; delete root; delete asset; }
				return EngineInstall.Install(task, selected, asset, root);
			});
		mTask.Start();
	}
	void OnDialogCancel() { mDialog.visible = false; }
	void OnDialogBackdrop() { }
	void OnCancel() { mTask?.Cancel(); }
	void OnShowSettings() { Find("settings").visible = true; Find("page").visible = false; }
	void OnOpenInstallFolder() { Machine.Open(mInstallPath); }
	void OnBetas() { }
	void OnSelectVersion(UIElement source) { }
	void OnLaunch() { }
	void OnShowFolder() { Machine.Open(mInstallPath); }
	void OnUninstall() { }
}
