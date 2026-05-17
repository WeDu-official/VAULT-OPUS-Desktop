import re

with open('src/WI/mobile/src/App.jsx', 'r') as f:
    content = f.read()

# Define the components to refactor
components = [
    "UploadForm", "DownloadForm", "DeleteForm", "MoveCopyForm",
    "ItemOptionsMenu", "RenameItemForm", "NewVersionForm", "MakeFolderForm",
    "VolumeOptions", "NukeConfirmation", "SharablesView", "RenameVolumeForm",
    "ImportForm", "FullNameInfo", "VersionsView", "DownloadVersionView"
]

# We need to extract the block containing all these from inside App()
# App() starts around line 372
# The components start around line 742 and end around 1545

start_marker = "  const UploadForm = () => {"
end_marker = "  // ─────────────────── MAIN RENDER ───────────────────"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("Markers not found")
    exit(1)

extracted_block = content[start_idx:end_idx]
remaining_content = content[:start_idx] + content[end_idx:]

# Now, we need to inject the useContext line into each component
context_injection = "    const { selectedDb, currentPath, selectedItems, dbs, queue, ws, terminalOutput, recentVolumes, externalVolumes, runCmd, showToast, fetchFiles, fetchDbs, setBottomSheet, setModal, setSelectedDb, setTab, setExternalVolumes, setDbs, setSelectedItems, handleSeeVersions, handleDownloadVersion } = React.useContext(AppContext);\n"

# We can regex replace the start of each component
for comp in components:
    # Match: const CompName = ({ props }) => { or const CompName = () => {
    pattern = r"(const " + comp + r" = \([^)]*\) => \{)"
    def replacer(match):
        return match.group(1) + "\n" + context_injection
    extracted_block = re.sub(pattern, replacer, extracted_block)

# We need to define AppContext at the top of the file
if "export const AppContext" not in remaining_content:
    import_idx = remaining_content.find("const Ico = {")
    remaining_content = remaining_content[:import_idx] + "export const AppContext = React.createContext();\n\n" + remaining_content[import_idx:]

# We need to wrap the App return in AppContext.Provider
# Wait, let's inject the context value definition inside App
app_start_idx = remaining_content.find("export default function App() {")
# Find the line before return
return_idx = remaining_content.find("return (", app_start_idx)

context_value_def = """
  const appCtxValue = {
    selectedDb, currentPath, selectedItems, dbs, queue, ws, terminalOutput,
    recentVolumes, externalVolumes, runCmd, showToast, fetchFiles, fetchDbs,
    setBottomSheet, setModal, setSelectedDb, setTab, setExternalVolumes,
    setDbs, setSelectedItems, handleSeeVersions, handleDownloadVersion
  };
"""

remaining_content = remaining_content[:return_idx] + context_value_def + "\n  " + remaining_content[return_idx:]

# Replace `return (` with `return (\n    <AppContext.Provider value={appCtxValue}>`
remaining_content = remaining_content.replace(
    "return (\n    <div className=\"flex flex-col h-full safe-top bg-[#060d1a]\">",
    "return (\n    <AppContext.Provider value={appCtxValue}>\n    <div className=\"flex flex-col h-full safe-top bg-[#060d1a]\">"
)

# Replace the end of App() with `    </AppContext.Provider>\n  )\n}`
remaining_content = remaining_content.replace(
    "      {promptData && <PromptForm promptData={promptData} ws={ws} onClose={() => setPromptData(null)} />}\n    </div>\n  )\n}",
    "      {promptData && <PromptForm promptData={promptData} ws={ws} onClose={() => setPromptData(null)} />}\n    </div>\n    </AppContext.Provider>\n  )\n}"
)

# Append extracted_block at the end of the file
final_content = remaining_content + "\n" + extracted_block

with open('src/WI/mobile/src/App.jsx.new', 'w') as f:
    f.write(final_content)

print("Done")
