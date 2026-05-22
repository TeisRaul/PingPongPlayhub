import os

def main():
    file_path = r"c:\Users\teisr\Desktop\PingPongPlayhub\PingPongPlayhub\lib\screens\login_screen.dart"
    
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Find the start of _generateDemoAccounts and the end of _buildQuickLoginButton
    start_marker = "  Future<void> _generateDemoAccounts() async {"
    end_marker = "  Widget _buildQuickLoginButton(String label, String email) {"
    
    # We want to remove from start_marker to the end of the _buildQuickLoginButton method
    # Let's find the index of the start marker
    start_idx = content.find(start_marker)
    if start_idx == -1:
        print("Could not find start marker in file.")
        return

    # Let's find the @override that comes after the quick login button
    # Since the quick login button ends with a closing brace followed by an empty line and then @override Widget build
    target_override = "@override\n  Widget build(BuildContext context) {"
    override_idx = content.find(target_override)
    if override_idx == -1:
        # try with other line endings
        target_override = "@override\r\n  Widget build(BuildContext context) {"
        override_idx = content.find(target_override)

    if override_idx == -1:
        print("Could not find override marker in file.")
        return

    # Slice out the injected methods (along with whitespace)
    # The start_idx should include the empty line before it if possible, or we can just strip it
    # Let's inspect the content to cut it cleanly
    injected_methods = content[start_idx:override_idx]
    
    # Remove it
    new_content = content[:start_idx] + content[override_idx:]

    # Now let's remove the developer zone UI at the bottom
    # It starts with 'const SizedBox(height: 16),\n              const Divider(color: Colors.grey),'
    # and ends with '_buildQuickLoginButton(\'Jucător 8 (Plat)\', \'jucator8@test.com\'),\n                ],\n              ),'
    
    ui_start_marker = "const SizedBox(height: 16),\n              const Divider(color: Colors.grey),"
    if ui_start_marker not in new_content:
        ui_start_marker = "const SizedBox(height: 16),\r\n              const Divider(color: Colors.grey),"

    ui_start_idx = new_content.find(ui_start_marker)
    if ui_start_idx == -1:
        print("Could not find UI start marker in file.")
        # Try a simpler marker
        ui_start_marker = "const Divider(color: Colors.grey),"
        ui_start_idx = new_content.find(ui_start_marker)
        if ui_start_idx != -1:
            # step back to include the SizedBox if we can
            pass

    if ui_start_idx == -1:
        print("Could not find UI start marker in file.")
        return

    # Let's find where the Wrap ends
    # The developer zone ends right before '],', which is the closing bracket of the Column
    # Let's find the closing column structure
    ui_end_marker = "],\n          ),"
    if ui_end_marker not in new_content:
        ui_end_marker = "],\r\n          ),"

    # Let's find the closing column starting from ui_start_idx
    ui_end_idx = new_content.find(ui_end_marker, ui_start_idx)
    if ui_end_idx == -1:
        print("Could not find UI end marker in file.")
        return

    # Slice out the developer zone UI
    # We want to keep the closing '],' of the column
    developer_zone_ui = new_content[ui_start_idx:ui_end_idx]
    
    # We want to remove the developer zone UI completely, but leave the Column closing
    final_content = new_content[:ui_start_idx] + new_content[ui_end_idx:]

    # Write it back!
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(final_content)

    print("SUCCESS: login_screen.dart reverted successfully!")

if __name__ == '__main__':
    main()
