#!/usr/bin/env python3
"""ネクストファイナンス ハンズオン：Gmail / Google Chat 実データ（メール＆チャット）一括投入スクリプト.

講師アカウント（user00 / student-00）の OAuth アクセストークンを使用して、
プロジェクト内の全受講者アカウント（student-00 〜 student-10 等）に対して：
1. Gmail API で「東都ロジスティクス株式会社からの支払期日延長要請」相談メールおよび
   審査部・債権管理室からの一次返信メール（計2通・同一スレッド）を送信する。
2. Google Chat API でスペース「【審査部×ビリング債権管理】与信・収納モニタリング連携」を作成し、
   全受講者をメンバー追加した上で、審査部・料金センター・債権管理室の議論メッセージ（3件）を投稿する。
"""

import argparse
import base64
from email.header import Header
from email.mime.text import MIMEText
from email.utils import formataddr, formatdate, make_msgid
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


CHAT_SPACE_DISPLAY_NAME = (
    "【審査部×ビリング債権管理】与信・収納モニタリング連携"
)
EMAIL_SUBJECT = "【至急ご相談】多回線一括請求の大口契約先「東都ロジスティクス株式会社（Toto Logistics）」様からの支払期日延長要請について"

EMAIL_BODY_1 = """ビリング事業本部 債権管理室長 殿
審査部 審査第一課長 殿
（CC：経営企画部 各位）

お疲れ様です。法人営業第一部 課長の佐藤 健一です。（記録日時：2026年10月2日 14:20）

弊社「法人おまとめ請求（多回線一括請求・法人ビリングONE）」の大口契約先である「東都ロジスティクス株式会社（Toto Logistics）」様（契約者ID：CUST-1042）より、通信料金・車載端末割賦代金の支払期日延長（支払猶予）に関する緊急の要請がございましたので、経緯のご報告と決裁ルートの確認をお願いいたします。

■ 1. 対象契約先・契約規模・相談経緯
・対象契約先：東都ロジスティクス株式会社（Toto Logistics ／ 中堅物流業 ／ 契約者ID：CUST-1042 ／ 社内与信ランク：C1）
・契約内容：全国180拠点の光回線・NW、および配送ドライバー用モバイル・車載IoT回線（計4,850回線）の多回線一括請求
・現行の与信限度額：月間 6,000万円
・直近の月間請求額：約 4,800万円（内訳：通信・NW費 3,100万円、車載端末割賦・合算分 1,700万円）
・先方からの要請内容：燃料費高騰および主要荷主からの運賃回収サイト長期化により運転資金が一時逼迫しているため、2026年10月・11月請求分の支払期日を現行の「翌月末払い（30日サイト）」から「翌々月末払い（60日サイト）」へ1ヶ月延長（支払猶予）してほしいとの要請。
・過去の遅延履歴と営業懸念：同社は直近6ヶ月以内（2026年5月・8月）に口座振替が資金不足で不調となり、払込票・銀行振込での事後入金（5〜8日遅延）となった事象が計2回発生している。一方で来期に車載IoT回線800回線の追加増設案件を控えており、決裁権限（経営会議付議の要否）と新規増設への影響を確認したい。

■ 2. 確認・相談事項
(1) 本件（月間請求額 4,800万円・直近6ヶ月遅延2回・与信ランクC1）の支払期日延長（30日サイト→60日サイト）について、営業本部長決裁で可能か、あるいは経営会議への付議・承認が必須となるか。
(2) 来期に予定している新規の「車載IoT回線 800回線」の追加増設案件への影響（与信枠凍結や圧縮、前受保証金・売掛債権保証などの保全条件）。

至急のご確認をお願いいたします。
"""

EMAIL_BODY_2 = """法人営業第一部 佐藤課長
（CC：ビリング事業本部 債権管理室、経営企画部 各位）

お疲れ様です。審査部 第一課長の山本 裕介です。
東都ロジスティクス株式会社（Toto Logistics / 契約者ID：CUST-1042）様の支払期日延長（60日サイト化）のご相談について、本日（2026年10月3日）Google Chat の「【審査部×ビリング債権管理】与信・収納モニタリング連携」スペースにて料金センターおよび債権管理室と緊急協議を行いましたので、現場の懸念点と規程上の判断を共有します。

■ 1. 審査部・料金センター現場での懸念点（類似相談の急増トレンド）
・【審査部 第一課長 山本 裕介】：
  東都ロジスティクス（株）（CUST-1042 / 4,850回線・月間請求4,800万円）は直近6ヶ月で口座振替不能による入金遅延が2回（2026年5月・8月）あり、社内与信ランクが『C1（要注意）』に下がっています。実は今月に入って、同じ『物流・運輸セクター』や『建設・不動産セクター』の多回線一括契約先（ランクC1〜C2）から、同種の支払サイト延長・分割払いの相談が他に6社も相次いでいます。
・【ビリング事業本部 料金センター 高橋 誠】：
  法人大口だけでなく、大多数の請求先である『個人の回線契約者（モバイル・光・おまとめ請求）』側でも要注意トレンドが出ています。口座振替・クレカ正常決済層は収納率99.7%と健全ですが、初回口座振替不能でコンビニ払込票（紙）に切り替わった与信ランクC1/C2層（特に電話料金合算サービスを上限近く利用している層）で期日超過・未収率が 14.8% に急上昇しており、払込票の再発行郵送費と督促稼働が現場を圧迫しています。

■ 2. 社内規程（『通信料金等債権管理および与信運用規程』）上の決裁条件・保全措置
・【債権管理室 主任 渡辺 彩】：
  『通信料金等債権管理および与信運用規程』の第11条・第14条・第18条を確認しました。
  - 第11条（社内与信ランク定義）：直近6ヶ月以内に2回の引落不能・入金遅延が発生した先は「ランクC1（要注意）」に指定され、2回目の遅延発生時点で与信枠20%圧縮の対象となります。
  - 第14条（支払期日延長・支払猶予等の決裁権限基準）：東都ロジスティクス社（①月間請求額3,000万円以上の大口契約先 かつ ②直近6ヶ月以内に2回以上の入金遅延履歴がある要注意先ランクC1）の期日延長（30日サイト→60日サイト）は、営業本部長決裁は不可であり、『審査部長およびビリング事業本部長の合議の上、経営会議（またはリスク管理委員会）への付議・承認』が必須です。
  - 第18条（支払猶予申請時における与信枠の自動凍結および債権保全措置）：支払猶予申請を受理した時点で以下3点の保全措置がすべて必須となります。
    ① 新規与信枠・回線増設の一時凍結：予定されている『車載IoT回線800回線の追加増設・新規割賦枠拡大』は原則として全面凍結（支払猶予期間中および正常化後6ヶ月間）。
    ② 与信限度額の20%圧縮：現行の与信限度額（月間6,000万円）の未使用枠を即時カットし、現行与信枠の80%相当（4,800万円：20%圧縮）を上限として再設定。
    ③ 決済手段および債権保全条件の見直し：前受保証金（月間請求額の1ヶ月分以上）の預託、またはファクタリング（売掛債権保証 60%以上等）の付保を経営会議付議の前提条件とすること。

詳細は Google Chat スペース「【審査部×ビリング債権管理】与信・収納モニタリング連携」および社内規程PDF（通信料金等債権管理および与信運用規程 第11条・第14条・第18条）もあわせてご確認ください。
"""

CHAT_MESSAGES = [
    (
        "💬 **審査部 第一課長 山本 裕介 (2026年10月3日 11:10)**\n"
        "「法人営業第一部の佐藤課長から相談が来た『東都ロジスティクス株式会社（Toto Logistics）』（契約者ID：CUST-1042 / 計4,850回線・月間請求約4,800万円［通信・NW費3,100万円、車載端末割賦・合算分1,700万円］・現行与信限度額6,000万円）の支払期日延長（翌月末30日サイト→翌々月末60日サイト化）の件ですが、"
        "同社は直近6ヶ月（2026年5月・8月）で口座振替不能による入金遅延（5〜8日遅延）が計2回あり、与信ランクが『C1（要注意）』に下がっています。\n"
        "実は今月に入って、同じ『物流・運輸セクター』や『建設・不動産セクター』の多回線一括契約先（ランクC1〜C2）から、燃料費高騰や荷主回収サイト長期化を理由とした同種の支払サイト延長・分割払いの相談が他に6社も相次いでいます。」"
    ),
    (
        "💬 **ビリング事業本部 料金センター 高橋 誠 (2026年10月3日 11:22)**\n"
        "「法人大口だけでなく、大多数の請求先である『個人の回線契約者（モバイル・光・おまとめ請求）』側でも要注意トレンドが出ています。\n"
        "口座振替・クレジットカード正常決済層は収納率99.7%と健全ですが、初回口座振替不能でコンビニ払込票（紙請求書）に切り替わった与信ランクC1/C2層（特に電話料金合算サービスを上限近く利用している層）で期日超過・未収率が 14.8% に急上昇しており、払込票の再発行郵送費と督促稼働が現場を圧迫しています。」"
    ),
    (
        "💬 **債権管理室 主任 渡辺 彩 (2026年10月3日 11:30)**\n"
        "「『通信料金等債権管理および与信運用規程』の第11条・第14条・第18条を確認しました。\n"
        "東都ロジスティクス社（月間3,000万円以上 かつ 直近6ヶ月で遅延2回のランクC1）の支払期日延長は、第14条により営業本部長決裁は不可で『審査部長およびビリング事業本部長の合議の上、経営会議（またはリスク管理委員会）への付議・承認』が必須です。\n"
        "さらに第18条により、支払猶予申請を受理した時点で『来期予定されている車載IoT回線800回線の追加増設・割賦枠拡大は全面凍結』し、『与信限度額の20%圧縮（月間6,000万円→4,800万円）』および『前受保証金（月間請求額1ヶ月分以上）またはファクタリング（売掛債権保証60%以上）付保』を経営会議付議の前提条件とする必要があります。」"
    ),
]


def api_request(
    url: str,
    token: str,
    project_id: str,
    method: str = "GET",
    payload: dict | None = None,
    timeout: int = 20,
) -> dict:
  headers = {
      "Authorization": f"Bearer {token}",
      "Content-Type": "application/json",
  }
  if project_id:
    headers["X-Goog-User-Project"] = project_id
  data = None
  if payload is not None:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
  req = urllib.request.Request(url, data=data, headers=headers, method=method)
  with urllib.request.urlopen(req, timeout=timeout) as resp:
    raw = resp.read().decode("utf-8")
    return json.loads(raw) if raw else {}


def discover_project_users(project_id: str) -> list[str]:
  users = set()
  try:
    out = subprocess.check_output(
        ["gcloud", "projects", "get-iam-policy", project_id, "--format=json"],
        stderr=subprocess.DEVNULL,
        text=True,
    )
    policy = json.loads(out)
    for b in policy.get("bindings", []):
      for m in b.get("members", []):
        if m.startswith("user:"):
          email = m.split("user:", 1)[1].strip()
          if "@" in email:
            users.add(email)
  except Exception:
    pass

  try:
    active_acc = subprocess.check_output(
        ["gcloud", "config", "get-value", "account"],
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
    if "@" in active_acc and not active_acc.endswith(".gserviceaccount.com"):
      users.add(active_acc)
  except Exception:
    pass

  return sorted(users)


def build_raw_email(
    sender_display: str,
    sender_email: str,
    to_emails: list[str],
    subject: str,
    body: str,
    in_reply_to: str | None = None,
) -> tuple[str, str]:
  msg = MIMEText(body, "plain", "utf-8")
  msg["Subject"] = str(Header(subject, "utf-8"))
  msg["From"] = formataddr((str(Header(sender_display, "utf-8")), sender_email))
  msg["To"] = ", ".join(to_emails)
  msg["Date"] = formatdate(localtime=True)
  msg_id = make_msgid(domain=sender_email.split("@")[-1] if "@" in sender_email else "next-finance.local")
  msg["Message-ID"] = msg_id
  if in_reply_to:
    msg["In-Reply-To"] = in_reply_to
    msg["References"] = in_reply_to
  raw_bytes = msg.as_bytes()
  encoded = base64.urlsafe_b64encode(raw_bytes).decode("ascii").rstrip("=")
  return encoded, msg_id


def seed_gmail(
    token: str,
    project_id: str,
    recipients: list[str],
    force: bool = False,
) -> tuple[bool, str]:
  try:
    profile = api_request(
        "https://gmail.googleapis.com/gmail/v1/users/me/profile",
        token,
        project_id,
    )
    sender_email = profile.get("emailAddress", "")
  except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8", errors="ignore")
    return False, f"Gmail API profile check failed (HTTP {e.code}): {err_body[:240]}"
  except Exception as e:
    return False, f"Gmail API connection error: {e}"

  if sender_email and sender_email not in recipients:
    recipients = [sender_email] + recipients
  if not recipients and sender_email:
    recipients = [sender_email]

  if not force:
    try:
      q = urllib.parse.quote("CUST-1042 東都ロジスティクス")
      existing = api_request(
          f"https://gmail.googleapis.com/gmail/v1/users/me/messages?q={q}",
          token,
          project_id,
      )
      if existing.get("messages"):
        return (
            True,
            f"Gmail messages already seeded in {sender_email} (found {len(existing['messages'])} messages for CUST-1042).",
        )
    except Exception:
      pass

  # Send Message 1 (Sales consultation email)
  raw1, msg_id_1 = build_raw_email(
      sender_display="法人営業第一部 課長 佐藤 健一",
      sender_email=sender_email,
      to_emails=recipients,
      subject=EMAIL_SUBJECT,
      body=EMAIL_BODY_1,
  )
  try:
    sent1 = api_request(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        token,
        project_id,
        method="POST",
        payload={"raw": raw1},
    )
    thread_id = sent1.get("threadId")
    msg1_api_id = sent1.get("id")
    if msg1_api_id:
      try:
        api_request(
            f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{msg1_api_id}/modify",
            token,
            project_id,
            method="POST",
            payload={"addLabelIds": ["INBOX", "IMPORTANT"]},
        )
      except Exception:
        pass
  except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8", errors="ignore")
    return False, f"Gmail send message 1 failed (HTTP {e.code}): {err_body[:240]}"
  except Exception as e:
    return False, f"Gmail send message 1 error: {e}"

  time.sleep(1)

  # Send Message 2 (Reply in the same thread)
  raw2, _ = build_raw_email(
      sender_display="審査部 第一課長 山本 裕介 / 債権管理室",
      sender_email=sender_email,
      to_emails=recipients,
      subject=f"Re: {EMAIL_SUBJECT}",
      body=EMAIL_BODY_2,
      in_reply_to=msg_id_1,
  )
  payload2 = {"raw": raw2}
  if thread_id:
    payload2["threadId"] = thread_id
  try:
    sent2 = api_request(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        token,
        project_id,
        method="POST",
        payload=payload2,
    )
    msg2_api_id = sent2.get("id")
    if msg2_api_id:
      try:
        api_request(
            f"https://gmail.googleapis.com/gmail/v1/users/me/messages/{msg2_api_id}/modify",
            token,
            project_id,
            method="POST",
            payload={"addLabelIds": ["INBOX", "IMPORTANT"]},
        )
      except Exception:
        pass
  except Exception as e:
    return (
        True,
        f"Gmail primary consultation email sent to {len(recipients)} recipients (reply warning: {e}).",
    )

  return (
      True,
      f"Sent 2 consultation thread emails from {sender_email} to {len(recipients)} recipients ({', '.join(recipients)}).",
  )


def seed_google_chat(
    token: str,
    project_id: str,
    recipients: list[str],
    sender_email: str = "",
    force: bool = False,
) -> tuple[bool, str]:
  space_name = ""
  try:
    spaces_resp = api_request(
        "https://chat.googleapis.com/v1/spaces?pageSize=100",
        token,
        project_id,
    )
    for sp in spaces_resp.get("spaces", []):
      if sp.get("displayName") == CHAT_SPACE_DISPLAY_NAME:
        space_name = sp.get("name", "")
        break
  except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8", errors="ignore")
    return False, f"Google Chat API list spaces failed (HTTP {e.code}): {err_body[:240]}"
  except Exception as e:
    return False, f"Google Chat API connection error: {e}"

  other_users = [
      u
      for u in recipients
      if u and u.lower() != sender_email.lower() and not u.endswith(".gserviceaccount.com")
  ]

  created_new_space = False
  if not space_name:
    # First attempt spaces:setup with memberships
    setup_memberships = [
        {
            "member": {
                "name": f"users/{u}",
                "type": "HUMAN",
            }
        }
        for u in other_users
    ]
    setup_payload = {
        "space": {
            "spaceType": "SPACE",
            "displayName": CHAT_SPACE_DISPLAY_NAME,
            "externalUserAllowed": True,
        },
    }
    if setup_memberships:
      setup_payload["memberships"] = setup_memberships

    try:
      sp_res = api_request(
          "https://chat.googleapis.com/v1/spaces:setup",
          token,
          project_id,
          method="POST",
          payload=setup_payload,
      )
      space_name = sp_res.get("name", "")
      created_new_space = True
    except Exception:
      # Fallback: create space first, then add members one by one
      try:
        sp_res = api_request(
            "https://chat.googleapis.com/v1/spaces",
            token,
            project_id,
            method="POST",
            payload={
                "spaceType": "SPACE",
                "displayName": CHAT_SPACE_DISPLAY_NAME,
                "externalUserAllowed": True,
            },
        )
        space_name = sp_res.get("name", "")
        created_new_space = True
      except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="ignore")
        return False, f"Google Chat space creation failed (HTTP {e.code}): {err_body[:240]}"
      except Exception as e:
        return False, f"Google Chat space creation error: {e}"

  if not space_name:
    return False, "Google Chat space name could not be resolved."

  # Ensure all other lab users are added as members (best-effort per user)
  added_members = 0
  for u in other_users:
    try:
      api_request(
          f"https://chat.googleapis.com/v1/{space_name}/members",
          token,
          project_id,
          method="POST",
          payload={
              "member": {
                  "name": f"users/{u}",
                  "type": "HUMAN",
              }
          },
      )
      added_members += 1
    except Exception:
      pass

  # Check if messages already exist in the space when reusing an existing space
  if not created_new_space and not force:
    try:
      msgs_resp = api_request(
          f"https://chat.googleapis.com/v1/{space_name}/messages?pageSize=20",
          token,
          project_id,
      )
      existing_msgs = msgs_resp.get("messages", [])
      if any("CUST-1042" in m.get("text", "") for m in existing_msgs):
        return (
            True,
            f"Google Chat space '{CHAT_SPACE_DISPLAY_NAME}' ({space_name}) already has CUST-1042 messages (newly added members: {added_members}).",
        )
    except Exception:
      pass

  posted_count = 0
  for msg_text in CHAT_MESSAGES:
    try:
      api_request(
          f"https://chat.googleapis.com/v1/{space_name}/messages",
          token,
          project_id,
          method="POST",
          payload={"text": msg_text},
      )
      posted_count += 1
      time.sleep(0.5)
    except urllib.error.HTTPError as e:
      err_body = e.read().decode("utf-8", errors="ignore")
      return (
          posted_count > 0,
          f"Posted {posted_count}/{len(CHAT_MESSAGES)} messages to {space_name}; error (HTTP {e.code}): {err_body[:200]}",
      )
    except Exception as e:
      return (
          posted_count > 0,
          f"Posted {posted_count}/{len(CHAT_MESSAGES)} messages to {space_name}; error: {e}",
      )

  return (
      True,
      f"Created/updated space '{CHAT_SPACE_DISPLAY_NAME}' ({space_name}), posted {posted_count} messages, invited {len(other_users)} lab accounts.",
  )


def main() -> int:
  parser = argparse.ArgumentParser(
      description="Seed Gmail and Google Chat data for Next Finance hands-on."
  )
  parser.add_argument("--project-id", default="", help="GCP Project ID")
  parser.add_argument(
      "--token",
      default="",
      help="OAuth2 access token with Gmail and Google Chat scopes",
  )
  parser.add_argument(
      "--users",
      default="",
      help="Space or comma-separated list of user emails (auto-discovered if omitted)",
  )
  parser.add_argument(
      "--force",
      action="store_true",
      help="Force re-sending emails and chat messages even if already present",
  )
  parser.add_argument(
      "--json-output",
      default="",
      help="Optional path to write JSON status result",
  )
  args = parser.parse_args()

  project_id = args.project_id or os.environ.get("PROJECT_ID", "")
  if not project_id:
    try:
      project_id = subprocess.check_output(
          ["gcloud", "config", "get-value", "project"],
          stderr=subprocess.DEVNULL,
          text=True,
      ).strip()
    except Exception:
      project_id = ""

  token = args.token or os.environ.get("GWS_ACCESS_TOKEN", "")
  if not token:
    for cmd in (
        ["gcloud", "auth", "application-default", "print-access-token"],
        ["gcloud", "auth", "print-access-token"],
    ):
      try:
        t = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True).strip()
        if t:
          token = t
          break
      except Exception:
        continue

  if args.users:
    raw_users = args.users.replace(",", " ").split()
    users = sorted({
        u.replace("user:", "").strip()
        for u in raw_users
        if "@" in u and not u.endswith(".gserviceaccount.com")
    })
  else:
    users = discover_project_users(project_id)

  print(f"  -> Target lab user accounts ({len(users)}): {', '.join(users) if users else 'auto (me)'}")

  gmail_ok, gmail_msg = seed_gmail(token, project_id, users, force=args.force)
  if gmail_ok:
    print(f"  [OK] Gmail: {gmail_msg}")
  else:
    print(f"  [WARN] Gmail: {gmail_msg}")

  sender_email = ""
  try:
    prof = api_request(
        "https://gmail.googleapis.com/gmail/v1/users/me/profile",
        token,
        project_id,
    )
    sender_email = prof.get("emailAddress", "")
  except Exception:
    pass

  chat_ok, chat_msg = seed_google_chat(
      token, project_id, users, sender_email=sender_email, force=args.force
  )
  if chat_ok:
    print(f"  [OK] Google Chat: {chat_msg}")
  else:
    print(f"  [WARN] Google Chat: {chat_msg}")

  result = {
      "gmail_seeded": gmail_ok,
      "gmail_message": gmail_msg,
      "chat_seeded": chat_ok,
      "chat_message": chat_msg,
      "users": users,
  }
  if args.json_output:
    with open(args.json_output, "w", encoding="utf-8") as f:
      json.dump(result, f, ensure_ascii=False, indent=2)

  return 0 if (gmail_ok and chat_ok) else (0 if gmail_ok else 1)


if __name__ == "__main__":
  sys.exit(main())
