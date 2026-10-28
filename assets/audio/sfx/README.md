# 音效资源

音效由 `tools/generate_ui_sfx.py` 合成，不含第三方录音采样。

文件格式为44.1kHz、16bit、单声道 WAV。

| 文件 | 用途 | 时长 |
| --- | --- | --- |
| `ui_click.wav` | 按钮确认 | 0.09秒 |
| `card_play.wav` | 出牌滑动 | 0.26秒 |
| `effect_arrive.wav` | 效果数字到达指标或修正栏 | 0.20秒 |
| `turn_settle.wav` | 数值结算完成 | 0.27秒 |
| `reward_gain.wav` | 领取奖励、任命内阁 | 0.68秒 |
| `event_alert.wav` | 事件出现 | 0.60秒 |
| `victory.wav` | 获胜 | 1.18秒 |
| `defeat.wav` | 失败 | 1.05秒 |

播放由 `presentation/sfx_audio.gd` 管理，使用6个通道并限制连续触发频率。顶部可静音、调节音量，设置保存在 `user://audio.cfg`。游戏没有背景音乐。

在项目根目录重新生成全部音效：

```sh
python tools/generate_ui_sfx.py
```

只生成指定文件：

```sh
python tools/generate_ui_sfx.py --only card_play.wav turn_settle.wav
```
