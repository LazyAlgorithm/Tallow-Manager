using System;
using System.IO;
using System.Collections;
using Tallow;

namespace TallowManager;

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
	String mSelectedPath = new .() ~ delete _;
	String mSelectedTag = new .() ~ delete _;
	bool mDialogTools;
	List<Catalog.Dependency> mMissingTools = new .() ~ delete _;
	bool mChecking;
	bool mReady;

	public override void Start()
	{
		mInstallPath.Set(Machine.ToolsFolder);
		mInstallPath.Append("/../engines");
		Directory.CreateDirectory(scope $"{mInstallPath}/versions").IgnoreError();
		Library.Load();
		Library.Betas = true;
		Library.SaveState();
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
			Find("betatoggle").value = 1;
			Find("progress").visible = false;
			Find("message").visible = false;
			Find("launchbutton").visible = false;
			Find("removebutton").visible = false;
			Find("folderbutton").visible = false;
			Find("primary").SetText("CHECK FOR RELEASES");
			Find("summary").SetText("Install Tallow engine builds side by side. No Python required to download an engine.");
			mReady = true;
			RefreshInstalled();
			CheckReleases();
			CheckManagerUpdate();
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
				let completedToolchain = mTask.For == "toolchain";
				let managerCheck = mTask.For == "manager-check";
				let managerUpdate = mTask.For == "manager-update";
				mError.Clear();
				if (!success) mTask.GetError(mError);

				if (!managerCheck)
				{
					Find("message").visible = true;
					Find("message").SetText(success ? (managerUpdate ? "Restarting Manager..." : completedToolchain ? "Build tools installed. Restart Tallow to use them." : "Engine and required development tools installed successfully.") : mError);
					Find("message").SetClass("messageok", success);
				}
				delete mTask;
				mTask = null;
				Find("progress").visible = false;
				if (managerCheck)
				{
					if (success) Library.Poll();
					RefreshManagerUpdate();
				}
				else if (managerUpdate && success)
				{
					Library.RestartHub();
					Application.Instance.Running = false;
				}
				else if (success && !completedToolchain)
				{
					RefreshInstalled();
					CheckReleases();
				}
			}
		}
	}

	void CheckManagerUpdate()
	{
		if (mTask != null) return;
		mTask = new Task("Checking Manager updates", "manager-check", new (task) => Library.Check(task));
		mTask.Start();
	}

	void RefreshManagerUpdate()
	{
		let panel = Find("managerupdate");
		panel.visible = Library.HubUpdate != null;
		if (Library.HubUpdate != null)
			Find("managerupdatetext").SetText(scope $"Manager {Library.HubUpdate.tag} is ready. Update and restart.");
	}

	void OnUpdateManager()
	{
		if (mTask != null || Library.HubUpdate == null) return;
		let release = new Release();
		Library.HubUpdate.CopyTo(release);
		mTask = new Task("Updating Tallow Manager", "manager-update", new [=](task) =>
		{
			defer delete release;
			return Library.UpdateHub(release, task);
		});
		mTask.Start();
	}

	void CheckReleases()
	{
		let item = Library.Catalog.FindItem("tallow");
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
		Find("title").SetText("Tallow Engine");
		let shortTag = scope String();
		ShortVersion(release.tag, shortTag);
		Find("factversion").SetText(shortTag);
		Find("factbuild").SetText("Verified during installation");
		Find("notes").SetText(release.notes);
		Find("primary").SetText("INSTALL VERSION");
		Find("primary").visible = true;
		Find("launchbutton").visible = false;
		Find("folderbutton").visible = false;
		Find("removebutton").visible = false;
		mSelectedPath.Clear();
		mSelectedTag.Clear();
		Find("factinstalled").SetText("Not installed");
		Clear(mAvailable);
		for (let installed in mInstalled.children)
		{
			let installedBuild = installed.attributes.Get("tag");
			let installedVersion = installed.attributes.Get("version");
			if ((!installedVersion.IsEmpty && release.tag == installedVersion) ||
				(!installedBuild.IsEmpty && release.tag.Contains(installedBuild)))
			{
				Find("primary").visible = false;
				Find("factinstalled").SetText("Installed");
				OnSelectVersion(installed);
				return;
			}
		}
		let entry = mTemplate.Clone();
		entry.attributes.Remove("id");
		entry.parent = mAvailable;
		mAvailable.children.Add(entry);
		for (let child in entry.children)
		{
			if (!child.HasClass("entrytext")) continue;
			for (let label in child.children)
			{
				if (label.HasClass("entryname")) label.SetText(shortTag);
				if (label.HasClass("entrystate")) label.SetText("Available");
			}
		}
	}

	void OnInstall()
	{
		if (mTask != null) return;
		for (let installed in mInstalled.children)
		{
			let version = installed.attributes.Get("version");
			let build = installed.attributes.Get("tag");
			if (mRelease != null && ((!version.IsEmpty && mRelease.tag == version) ||
				(!build.IsEmpty && mRelease.tag.Contains(build))))
			{
				OnSelectVersion(installed);
				Find("message").visible = true;
				Find("message").SetText("This engine version is already installed. Select Launch Engine or Uninstall.");
				return;
			}
		}
		if (mRelease == null)
		{
			Find("message").visible = true;
			Find("message").SetText("Release discovery is not yet connected. No files were changed.");
			return;
		}
		mDialogTools = false;
		mDialog.visible = true;
		let shortTag = scope String();
		ShortVersion(mRelease.tag, shortTag);
		Find("dialogtext").SetText(scope $"Install Tallow {shortTag} and its development tools? Windows may ask for administrator approval. This will not replace other engine versions.");
	}

	void OnDialogConfirm()
	{
		mDialog.visible = false;
		if (mDialogTools)
		{
			mDialogTools = false;
			if (mTask != null) return;
			let tools = new List<Catalog.Dependency>();
			tools.AddRange(mMissingTools);
			mMissingTools.Clear();
			mTask = new Task("Installing build tools", "toolchain", new [=](task) =>
			{
				defer delete tools;
				for (let dependency in tools)
					if (!Dependencies.IsFound(dependency) && !Dependencies.Install(dependency, task)) return false;
				return true;
			});
			mTask.Start();
			return;
		}
		if (mRelease == null || mTask != null) return;
		let selected = new Release();
		mRelease.CopyTo(selected);
		let root = new String(mInstallPath);
#if BF_PLATFORM_WINDOWS
		let asset = new String("Tallow-Windows.zip");
#else
		let asset = new String("Tallow-Linux.zip");
#endif
		mTask = new Task("Installing Tallow and development tools", "engine", new [=](task) =>
			{
				defer { delete selected; delete root; delete asset; }
				if (!EngineInstall.Install(task, selected, asset, root)) return false;
				let required = scope List<Catalog.Dependency>();
				let item = Library.Catalog.FindItem("tallow");
				if (item == null) return task.Fail("Installed engine, but toolchain requirements are missing from the catalog.");
				Dependencies.Missing(Library.Catalog, item, required);
				for (let dependency in required)
				{
					if (task.Cancelled) return task.Fail("Cancelled. Engine files were installed, but tool setup is incomplete.");
					if (!Dependencies.IsFound(dependency) && !Dependencies.Install(dependency, task))
						return false;
				}
				return true;
			});
		mTask.Start();
	}
	void OnDialogCancel() { mDialog.visible = false; mDialogTools = false; mMissingTools.Clear(); }
	void OnDialogBackdrop() { }
	void OnCancel() { mTask?.Cancel(); }
	void OnShowSettings() { Find("settings").visible = true; Find("page").visible = false; }
	void OnOpenInstallFolder() { Machine.Open(mInstallPath); }
	void OnBetas() { Library.Betas = true; Find("betatoggle").value = 1; Library.SaveState(); }

	static void ShortVersion(StringView tag, String output)
	{
		var value = tag;
		if (value.StartsWith("build-")) value = value.Substring(6);
		output.Append(value.Length > 12 ? value.Substring(0, 12) : value);
	}

	static void Clear(UIElement element)
	{
		ClearAndDeleteItems!(element.children);
	}

	void RefreshInstalled()
	{
		Clear(mInstalled);
		let versions = scope $"{mInstallPath}/versions";
		for (let versionDir in Directory.EnumerateDirectories(versions))
		{
			let versionPath = scope String();
			versionDir.GetFilePath(versionPath);
			for (let buildDir in Directory.EnumerateDirectories(versionPath))
			{
				let path = scope String();
				buildDir.GetFilePath(path);
				let manifestText = scope String();
				if (File.ReadAllText(scope $"{path}/tallow-version.json", manifestText) case .Err) continue;
				let manifest = SaveNode.FromText(manifestText);
				if (manifest == null) continue;
				let build = manifest["build"];
				let version = manifest["version"];
				if (build == null || build.kind != .String || version == null || version.kind != .String)
				{
					delete manifest;
					continue;
				}
				let entry = mTemplate.Clone();
				entry.attributes.Remove("id");
				entry.attributes.Set("path", path);
				entry.attributes.Set("tag", build.text);
				entry.attributes.Set("version", version.text);
				entry.parent = mInstalled;
				mInstalled.children.Add(entry);
				for (let child in entry.children)
				{
					if (!child.HasClass("entrytext")) continue;
					for (let label in child.children)
					{
						if (label.HasClass("entryname"))
							{
							let visibleVersion = scope String();
							ShortVersion(version.text, visibleVersion);
							label.SetText(scope $"Tallow {visibleVersion}");
						}
						if (label.HasClass("entrystate")) label.SetText("Installed — select to launch");
					}
				}
				delete manifest;
			}
		}
	}

	void OnSelectVersion(UIElement source)
	{
		let path = source.attributes.Get("path");
		if (path.IsEmpty) return;
		mSelectedPath.Set(path);
		mSelectedTag.Set(source.attributes.Get("tag"));
		Find("title").SetText("Tallow Engine");
		let label = scope String();
		ShortVersion(source.attributes.Get("version"), label);
		Find("factversion").SetText(label);
		Find("factinstalled").SetText("Installed");
		Find("launchbutton").visible = true;
		Find("launchbutton").SetText("LAUNCH ENGINE");
		Find("folderbutton").visible = true;
		Find("removebutton").visible = true;
		Find("primary").visible = false;
	}

	void OnLaunch()
	{
		if (mSelectedPath.IsEmpty) return;
#if BF_PLATFORM_WINDOWS
		let program = scope $"{mSelectedPath}/Tallow.exe";
#else
		let program = scope $"{mSelectedPath}/Tallow";
#endif
		if (File.Exists(program))
		{
			Machine.Start(program);
			mMissingTools.Clear();
			let item = Library.Catalog.FindItem("tallow");
			if (item != null) Dependencies.Missing(Library.Catalog, item, mMissingTools);
			if (!mMissingTools.IsEmpty)
			{
				mDialogTools = true;
				mDialog.visible = true;
				Find("dialogtitle").SetText("Set up Tallow build tools");
				let names = scope String();
				for (let tool in mMissingTools)
				{
					if (!names.IsEmpty) names.Append(", ");
					names.Append(tool.name);
				}
				Find("dialogtext").SetText(scope $"Tallow opened, but creating and building projects needs: {names}. Install these now? Administrator approval may be required.");
			}
		}
		else
		{
			Find("message").visible = true;
			Find("message").SetText("Engine executable missing from installed version.");
		}
	}
	void OnShowFolder() { Machine.Open(mSelectedPath.IsEmpty ? (StringView)mInstallPath : (StringView)mSelectedPath); }
	void OnUninstall()
	{
		if (mTask != null || mSelectedPath.IsEmpty) return;
		let deletedPath = scope String(mSelectedPath);
		let parent = scope String();
		Path.GetDirectoryPath(deletedPath, parent).IgnoreError();
		if (Directory.DelTree(deletedPath) case .Err || Directory.Exists(deletedPath))
		{
			Find("message").visible = true;
			Find("message").SetText("Could not remove the engine. Close it and try again.");
			return;
		}
		// Remove the empty version directory too; never remove another installed build.
		if (!parent.IsEmpty && Directory.Exists(parent))
		{
			bool containsBuilds = false;
			for (let remaining in Directory.EnumerateDirectories(parent))
			{
				containsBuilds = true;
				break;
			}
			if (!containsBuilds)
				Directory.DelTree(parent).IgnoreError();
		}
		mSelectedPath.Clear();
		mSelectedTag.Clear();
		Find("message").visible = true;
		Find("message").SetText("Engine version uninstalled. Shared development tools were kept.");
		Find("launchbutton").visible = false;
		Find("removebutton").visible = false;
		Find("folderbutton").visible = false;
		Find("primary").visible = true;
		RefreshInstalled();
		CheckReleases();
	}
}
