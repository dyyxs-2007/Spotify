#!/usr/bin/env python3
"""生成阶段一/二使用的本地 mock 数据（虚构的艺人/专辑/歌单）。
运行：python3 scripts/generate_mock.py  → 输出 Spotify/Resources/MockData/mock_data.json
"""
import json, random, os

random.seed(42)

PALETTE = ["#E13300", "#1E3264", "#8D67AB", "#148A08", "#E8115B", "#509BF5", "#BA5D07",
           "#27856A", "#AF2896", "#477D95", "#D84000", "#8C1932", "#006450", "#7358FF",
           "#B49BC8", "#E91429", "#0D73EC", "#A56752", "#503750", "#1D3D4E"]

def cover(seed):
    return f"https://picsum.photos/seed/sp-{seed}/600/600"

def audio(i):
    return f"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-{i % 16 + 1}.mp3"

artist_names = ["林知夏", "陈默", "苏野", "Echo Lane", "北岛乐队", "周屿", "Nova Kids", "许晴川"]
artists = [{"identifier": f"ar{i+1}", "name": n, "coverURL": cover(f"artist{i+1}")}
           for i, n in enumerate(artist_names)]

song_pool = [
    "晚风来信", "第七个夏天", "海盐汽水", "城市航线", "Neon Rain", "旧电台", "一万次日落", "无人知晓的星",
    "后来的我们", "Midnight Drive", "白日梦游", "雨停之前", "Paper Planes", "失眠飞行", "春日来信", "Glass Heart",
    "山海之间", "蓝色时刻", "慢慢喜欢你", "Lost in Tokyo", "回声", "云边书店", "Golden Hour", "十二月的风",
    "车窗外", "Satellite", "温柔宇宙", "不说再见", "Wildflower", "落日飞车", "灯火阑珊", "Daydream",
    "夏夜晚风", "人间烟火", "Ocean Eyes", "我们的歌", "远方来信", "Starlight", "孤独的鲸", "风吹麦浪",
    "Velvet Night", "晴天日记", "未完成的歌", "Runaway", "迷途", "Echoes", "凌晨三点", "月光海",
    "Blue Bird", "小情歌", "雾里看花", "Fireflies", "一个人的旅行", "Heartbeat", "向北走", "梦游仙境",
    "Sunday Morning", "时光机", "等风来", "Moonlight", "深海少女", "Breathe", "南方小镇", "Afterglow",
    "雪落下的声音", "Polaroid", "纸飞机", "Wanderer", "星河滚烫", "Home",
]
random.shuffle(song_pool)
song_iter = iter(song_pool)

album_defs = [
    ("夏日未眠", 0, 2025), ("城市夜行者", 1, 2024), ("野草与风", 2, 2023), ("Afterlight", 3, 2025),
    ("北方的岛", 4, 2022), ("屿", 5, 2026), ("Kids Don't Sleep", 6, 2024), ("晴川历历", 7, 2025),
    ("慢热", 0, 2021), ("Midnight Radio", 3, 2023),
]

tracks_by_id = {}
albums = []
audio_idx = 0
for ai, (name, ar_idx, year) in enumerate(album_defs):
    alb_id = f"al{ai+1}"
    color = PALETTE[ai % len(PALETTE)]
    alb_brief = {"identifier": alb_id, "name": name, "coverURL": cover(f"album{ai+1}"), "colorHex": color}
    tracks = []
    for _ in range(random.randint(6, 8)):
        t_name = next(song_iter, None) or f"Untitled {audio_idx}"
        tid = f"t{audio_idx+1}"
        artists_for_track = [artists[ar_idx]]
        if random.random() < 0.15:
            artists_for_track.append(artists[(ar_idx + 3) % len(artists)])
        t = {
            "identifier": tid, "name": t_name, "artists": artists_for_track,
            "album": alb_brief, "coverURL": cover(f"track-{tid}"),
            "duration": random.randint(165, 330), "audioURL": audio(audio_idx),
        }
        tracks_by_id[tid] = t
        tracks.append(t)
        audio_idx += 1
    albums.append({**alb_brief, "artists": [artists[ar_idx]], "releaseYear": year,
                   "albumType": "专辑" if len(tracks) > 6 else "EP", "tracks": tracks})

all_tracks = list(tracks_by_id.values())

playlist_defs = [
    ("liked", "已点赞的歌曲", "你点赞过的所有歌曲", "你", "#5038A0", 24),
    ("p1", "每日推荐", "根据你的口味，每天更新", "Spotify", "#1E3264", 20),
    ("p2", "夜晚的电台", "适合深夜独处时听的歌", "Spotify", "#503750", 18),
    ("p3", "专注时刻", "让你沉浸在工作和学习中", "Spotify", "#477D95", 15),
    ("p4", "华语流行精选", "最受欢迎的华语流行单曲", "Spotify", "#E8115B", 22),
    ("p5", "独立民谣", "木吉他与故事", "dyyxs", "#A56752", 14),
    ("p6", "运动燃脂", "高 BPM，停不下来", "Spotify", "#E13300", 16),
    ("p7", "雨天爵士", "窗外下雨，屋里有咖啡", "Spotify", "#27856A", 12),
    ("p8", "2026 年度热歌", "这一年你循环最多的旋律", "Spotify", "#7358FF", 25),
]
playlists = []
for pid, name, desc, creator, color, n in playlist_defs:
    playlists.append({
        "identifier": pid, "name": name, "desc": desc, "creatorName": creator,
        "coverURL": "" if pid == "liked" else cover(f"playlist-{pid}"), "colorHex": color,
        "followerCount": 0 if pid == "liked" else random.randint(1200, 2_800_000),
        "tracks": random.sample(all_tracks, min(n, len(all_tracks))),
    })

def ref(t, i): return {"type": t, "id": i}

home = [
    {"title": "", "style": "shortcut", "items": [ref("playlist", "liked"), ref("playlist", "p1"), ref("album", "al1"),
                                                 ref("playlist", "p2"), ref("album", "al4"), ref("playlist", "p3"),
                                                 ref("album", "al6"), ref("playlist", "p7")]},
    {"title": "为你推荐", "style": "card", "items": [ref("playlist", p) for p in ["p1", "p4", "p8", "p5", "p6", "p7"]]},
    {"title": "最近播放", "style": "card", "items": [ref("album", "al2"), ref("playlist", "p2"), ref("album", "al5"),
                                                   ref("album", "al8"), ref("playlist", "p3"), ref("album", "al10")]},
    {"title": "你常听的艺人", "style": "artist", "items": [ref("artist", a["identifier"]) for a in artists]},
    {"title": "热门新专辑", "style": "card", "items": [ref("album", f"al{i}") for i in [6, 1, 4, 7, 3, 9]]},
]

library = [ref("playlist", "liked"), ref("playlist", "p5"), ref("album", "al1"), ref("artist", "ar1"),
           ref("playlist", "p1"), ref("album", "al4"), ref("playlist", "p2"), ref("artist", "ar4"),
           ref("album", "al6"), ref("playlist", "p8"), ref("artist", "ar6"), ref("album", "al2"),
           ref("playlist", "p7"), ref("album", "al8"), ref("artist", "ar2")]

cat_names = ["流行", "华语", "摇滚", "民谣", "电子", "说唱", "爵士", "古典", "学习", "睡眠", "运动", "心情",
             "独立", "R&B", "怀旧", "派对"]
categories = [{"identifier": f"c{i+1}", "name": n, "colorHex": PALETTE[(i * 3) % len(PALETTE)],
               "coverURL": cover(f"cat{i+1}")} for i, n in enumerate(cat_names)]

data = {"artists": artists, "albums": albums, "playlists": playlists, "home": home,
        "library": library, "categories": categories}

out = os.path.join(os.path.dirname(__file__), "..", "Spotify", "Resources", "MockData", "mock_data.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=1)
print("tracks:", len(all_tracks), "albums:", len(albums), "playlists:", len(playlists), "->", os.path.abspath(out))
