# Display Deck

[English](README.md) | 繁體中文

專為 [niri](https://github.com/YaLTeR/niri) Wayland 合成器打造的原生
[Quickshell](https://quickshell.org/) / QML 螢幕管理工具。它會透過 `niri msg`
即時讀取各個輸出（output），讓你在視覺化畫布上排列、縮放、旋轉與開關顯示器，
接著同時套用到執行中的狀態（`niri msg output …`）並寫入持久化的
`~/.config/niri/monitor.kdl`。

![Display Deck](docs/screenshot.png)

## 功能特色

- **視覺化排版畫布** — 直接拖曳螢幕來擺位，內建邊緣吸附與碰撞處理，
  避免 niri 因螢幕重疊而默默拒絕擺放位置。
  - **左鍵拖曳** 移動單一螢幕。
  - **右鍵拖曳** 任意處平移整個視圖。
  - **◎ CENTER** 重新置中並縮放以顯示所有螢幕；**⊹ RESET** 將螢幕緊密並排對齊。
- **各螢幕獨立設定** — 開啟／關閉、解析度、更新率、縮放比例、旋轉、
  明確的 X/Y 座標，以及 VRR（若支援）。
- **Identify（識別）** — 在每台實體螢幕上閃示一個帶編號的霧面面板，方便對應。
- **自適應主題** — 顏色讀取自
  `~/.config/niri/colors.json` 或 `~/.config/noctalia/colors.json`
  （[Noctalia](https://github.com/noctalia-dev/noctalia-shell) Material 配色），
  並在整體 UI 採用琥珀色（主題 tertiary）的描邊點綴。
  若兩個檔案都不存在，則退回內建的深色主題。
- **真實合成器模糊** — 透過 niri 的 KDE blur 協定實現。

## 系統需求

- `niri`（需支援 `niri msg --json`）
- `quickshell`（`qs` 需在 `PATH` 中）
- `python3`（啟動器用來尋找既有視窗）

## 安裝

```sh
git clone https://github.com/shunlin-1/display-deck.git ~/Projects/display-deck
cd ~/Projects/display-deck
./install.sh
```

`install.sh` 會把 `bin/niri-displays` 連結（symlink）到 `~/.local/bin/`，
並把 `qml/shell.qml` 連結到 `~/.local/share/niri-displays/qml/`，
因此複製下來的儲存庫即為唯一的真實來源 —— 在這裡的修改會即時生效。

在 niri 設定中加入快捷鍵（`~/.config/niri/config.kdl`）：

```kdl
binds {
    Mod+Shift+T { spawn "niri-displays"; }
}
```

## 使用方式

執行 `niri-displays`（或使用快捷鍵）。啟動器為單一實例模式：
若 Display Deck 視窗已開啟，會直接聚焦到該視窗，而不會再開一個重複的。

排好顯示器後，按下 **APPLY** —— 它會即時套用，並寫入
`~/.config/niri/monitor.kdl`（同時把舊檔備份為 `monitor.kdl.bak`）。
在 niri 設定中 include 這個檔案，即可在重新開機後保留設定：

```kdl
// 於 ~/.config/niri/config.kdl
include "monitor.kdl"
```

## 授權條款

MIT —— 詳見 `LICENSE`（請自行加入）。
