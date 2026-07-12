# QA Packaging Retest Evidence

- Engine: Godot `4.7.stable.official.5b4e0cb0f`
- Preset check: `application/modify_resources=false`
- Formal package check: `build/` contained exactly `StarWorld.exe` and `StarWorld.pck`, with no `*.TMP`.
- Isolated command: `Godot_v4.7-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" .\tests\qa\export\StarWorld.exe`
- Isolated export result: exit `0`; no `ERROR`; exactly one EXE and one PCK; no `*.TMP`.
- Isolated launch: `StarWorld.exe --headless --quit-after 10`, exit `0`.
- Isolated EXE: 109,160,448 bytes; SHA-256 `C42EB5D17F683EB8BCD52C19A9F36EBF811B1788623878D5276A7D9FFC09F95C`.
- Isolated PCK: 165,196 bytes; SHA-256 `D612F90386C7E4B78B70F931B2EE946B0854D18E09051B6562615466DCFC4BE1`.
- The large isolated artifacts were deleted after verification; the formal `build/` package was not touched.
