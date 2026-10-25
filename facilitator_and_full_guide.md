# ネクストファイナンス：Gemini Enterprise ハンズオン（情報収集・社内調査・4部門データ分析＆多彩なチャート可視化）

本ドキュメントは、`explore.qwiklabs.com`（Labs for Sales）や Argolis 検証環境上で1つのラボ環境（**GCPプロジェクト1個＋ユーザーアカウント11個：`user00`［講師・管理者用］＋ `user01`〜`user10`［受講者9名＋予備1名］**）を払い出し、Gemini Notebook・Gemini Enterprise（GWS/社内文書横断検索 / モデル：`gemini-3.8-flash`）・**4種の部門別データ分析エージェント（BigQuery Conversational Analytics A2A連携：財務与信・コールセンターVOC・人事タレント・営業マーケROI）**を一気通貫で体験するための手順書です。

* **第1部**：ファシリテーター（講師）向け ラボ作成・当日12:00事前セットアップ・クリーンアップ手順（Cloud Shell ワンライナー方式 / 11アカウント対応）
* **第2部**：受講者（9名＋予備1名）向け ハンズオン手順書（基本45分コアシナリオ ＋ 4部門応用チャートショーケース）

---

## 第1部：ファシリテーター向け ラボ作成・事前セットアップ・削除手順

### 1. 初回のみ：explore.qwiklabs.com でのラボ枠（11ユーザー環境）の作成

`explore.qwiklabs.com` 上で **「GCPプロジェクト1個＋ユーザーアカウント11個（`user00`：管理者用1 ＋ `user01`〜`user10`：受講者用10）」** を払い出すラボ枠を作成します（Startup Script の複雑な審査・デバッグを不要にし、ラボ起動後に Cloud Shell からワンライナーで全環境を自動構築する方式です。Argolis 環境で事前検証する場合はそのまま「2. 自動構築手順」へ進んでください）。

1. シークレットウィンドウで `https://explore.qwiklabs.com` に `@google.com` アカウントでログインします。
   * 右上のアイコンからロールが **Creator** であることを確認します（Student の場合は `http://go/preregister` から Creator 権限を申請します）。
2. 左上のメニュー（`☰`）から **Authoring** → **Labs** を開き、右上の **[+ Create new lab]** → **GCP** を選択します。
3. 以下の基本項目を入力して **[Create Lab]** をクリックします。

| 設定項目 | 設定値 | 備考 |
| :--- | :--- | :--- |
| **Title** | ネクストファイナンス：Gemini Enterprise ハンズオン | 任意の識別しやすいタイトル |
| **Duration** | `180` | 当日12:00事前構築＋ハンズオン本番（45分）＋バッファ |
| **Max Duration** | `240` | 最大延長時間（4時間） |
| **Level** | `Intermediate` | 中級 |
| **Fleet / Variant** | `gcpd` | 標準 GCP プロジェクト |
| **Number of Users** | `11` | **`User 1`（`user00`: 講師・管理者用）＋ `User 2`〜`User 11`（`user01`〜`user10`: お客様受講者9名＋予備1名）** |

#### アカウント割当表（計11アカウント）

| ロールID | Qwiklabs 表示名 | 用途・割当先 | 備考 |
| :--- | :--- | :--- | :--- |
| **`user00`** | **`User 1`** | **ファシリテーター・管理者用（`tichiba` 操作用）** | Cloud Shell での `setup.sh` 実行・Gemini Enterprise 管理画面操作に使用 |
| **`user01` 〜 `user09`** | **`User 2` 〜 `User 10`** | **お客様受講者用（計9名：社長・取締役・部門長・課長様）** | 貸出 Chromebook 1号機〜9号機に事前ログインして配布 |
| **`user10`** | **`User 11`** | **お客様予備アカウント（1名分）** | 予備 Chromebook 10号機（または当日追加参加者・トラブル時切替用） |

4. 作成したラボの **Instructions** タブを開き、以下の **受講者向け Qwiklabs インポート専用 Google ドキュメント（45分コア体験版 / `qwiklabs-publisher@google.com` へ閲覧共有設定済）** の URL を貼り付けて **[Submit]** をクリックします：
   * **Qwiklabs Instructions 貼り付け用 URL**: [【Qwiklabsインポート用】NTTファイナンス様向け_Gemini_Enterprise_ハンズオン手順書（45分コア版）](https://docs.google.com/document/d/1_G7gWv6rbHZVNh9uJ-txBfanJL9FYCYNQ_Qnea25_FQ/edit) (`https://docs.google.com/document/d/1_G7gWv6rbHZVNh9uJ-txBfanJL9FYCYNQ_Qnea25_FQ/edit`)
5. **Environment Outputs** タブを開き、`Open Google Cloud Console`、`GCP Project ID`、および `User 1`（`user00`）〜 `User 11`（`user10`）のメールアドレス（Username）・共通パスワード（Password）・Google Drive リンクが表示されるよう設定して **[Update Environment Outputs]** を保存します。

---

### 2. 当日12:00（ハンズオン開始前）または Argolis 検証時：Cloud Shell 3分自動構築

10月30日（金）当日の会場入り・PC事前準備（12:00〜13:00）の際、または Argolis 環境での事前テスト時に、ファシリテーターがラボを1回起動し、`user00`（Qwiklabs `User 1`）の Cloud Shell からワンライナーで環境一式を構築します。

#### Step 1：Cloud Shell の起動と自動構築ワンライナーの実行（約3分）

1. Google Cloud コンソール右上の **Cloud Shell（`>_` アイコン）** を起動します（Qwiklabs の場合は管理者用の **`user00` ＝ `User 1`** でログインします）。
2. Cloud Shell で以下のコマンドをコピー＆ペーストして実行します（GitHub リポジトリから `next-finance-ge-handson-qwiklab.zip` を自動ダウンロードして展開し、`setup.sh` を実行します。手動での ZIP アップロードは不要です）。

```bash
curl -fL -o next-finance-ge-handson-qwiklab.zip https://raw.githubusercontent.com/tichiba/next-finance-ge-handson/main/docs/files/next-finance-ge-handson-qwiklab.zip && unzip -q -o next-finance-ge-handson-qwiklab.zip -d handson && bash handson/tf/scripts/setup.sh
```

* **PC上に構築用 ZIP を直接ダウンロードしたい場合の直リンク**：
  * `https://tichiba.github.io/next-finance-ge-handson/files/next-finance-ge-handson-qwiklab.zip`
  * （または `https://raw.githubusercontent.com/tichiba/next-finance-ge-handson/main/docs/files/next-finance-ge-handson-qwiklab.zip`）
* **受講者・講師用 Codelab URL（プロンプト1クリックコピー ＆ 統合報告書・IR資料ダウンロードページ）**：
  * `https://tichiba.github.io/next-finance-ge-handson/`

このコマンド1つで、以下の環境構築がすべて全自動で完了します。

| 自動構築される対象 | 構築内容の詳細 |
| :--- | :--- |
| **1. API 有効化・11アカウントIAM＆ライセンス構成** | `discoveryengine`、`geminidataanalytics`、`bigquery` 等のAPI有効化、プロジェクト内全11ユーザー（`user00`＋`user01`〜`user10`）への必須IAMロール付与、および Gemini Enterprise ライセンス自動割当設定 |
| **2. Cloud Storage 資料配置** | `gs://<PROJECT_ID>-next-finance-handson` を作成し、シナリオ1用 IR PDF（2点）、シナリオ2用 社内規程・メール・Chat履歴 PDF（2点）、および全4データセットのCSV・スキーマ一式をアップロード |
| **3. BigQuery 4データセット（計12テーブル）作成** | ① `next_finance_handson`（請求・入金・与信）<br>② `next_finance_callcenter`（コールセンター入電ログ・オペレーター・CSATアンケート）<br>③ `next_finance_hr`（社員マスタ・月次勤怠・エンゲージメントサーベイ）<br>④ `next_finance_sales_mktg`（マーケティング施策・見込み客リード・商談パイプライン） |
| **4. 社内規程データストア＆Gmail/Chatコネクタ＋実データ投入** | 講師アカウントでの初回1回 OAuth 認可により、全受講者へ「東都ロジスティクス相談メール（Gmail）」と「審査部・債権管理室スペース議論（Google Chat）」の実データを一括配信。さらに社内規程データストア（`next-finance-internal-docs`：規程PDFのみ）を作成し、**Gmail コネクタ（`google_mail`）・Google Chat コネクタ（`google_chat`）** を Gemini Enterprise に接続 |
| **5. Gemini Enterprise エンジン** | アプリ `ネクストファイナンス Gemini Enterprise ハンズオン`（`next-finance-ge-app`）を作成し、既定モデルに **`gemini-3.8-flash`** を設定してデータストアを紐付け |
| **6. 4種の A2A データ分析エージェント** | BigQuery Conversational Analytics 上に4つの部門別データエージェント（`請求・入金・与信分析` / `コールセンター分析` / `人事・タレント分析` / `営業・マーケROI分析`）を作成・公開し、Gemini Enterprise へ一括登録 |

#### Step 2：スクリプト実行中の OAuth 承認 ＆ Google Chat API 最小構成の保存（初回1回・約20秒）

スクリプトの `[2/6]` ステップで、全受講者アカウントへ実メール（Gmail）と実チャット（Google Chat）を自動配信するための案内が表示されます。

1. **OAuth 認可コードの入力**: 表示される URL を開き、講師アカウント（`user00`）で承認して verification code を貼り付けます（これだけで Gmail 2通が全11アカウントへ即座に配信されます）。
2. **Google Chat API 構成の保存（新規 Qwiklabs プロジェクト時）**:
   * Google Chat REST API の仕様上、新規プロジェクトでスペースを自動作成するには Cloud Console の「Google Chat API ＞ 構成」の保存が1回必要です。
   * ターミナルに表示される直リンク（`https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat?project=<PROJECT_ID>`）を開き、以下の最小設定を入力して **[保存 (Save)]** をクリックします（保存した瞬間にスクリプトが自動検知してスペース作成＆3件のメッセージ投稿を完了します）：
     * **アプリ名 (App name)**: `Next Finance Bot`
     * **アバターのURL (Avatar URL)**: `https://fonts.gstatic.com/s/e/notoemoji/latest/1f4ac/512.png`
     * **説明 (Description)**: `Next Finance Hands-on`
     * **機能 / 接続設定**: 「インタラクティブ機能を有効にする」のチェックを外す（または HTTP エンドポイント URL に `https://example.com` を入力）
   * ※後から Google Chat のみ再投入する場合は `python3 handson/tf/scripts/seed_gws_data.py --chat-only` を実行できます。

#### Step 3：Gemini Enterprise Web アプリ URL の取得と貸出 Chromebook の事前ログイン（5分）

1. スクリプト完了時に Cloud Shell に表示される **Gemini Enterprise 管理画面 URL**（またはコンソールの **AI Applications → Apps → ネクストファイナンス Gemini Enterprise ハンズオン**）を開きます。
2. 左メニューの **Integration（統合）** をクリックします。
   * **Identity Provider（ID プロバイダ）** が未設定の場合は、**Google Identity** を選択して **[Save]** をクリックします。
3. 画面中段に表示される **Web App URL（`https://vertexaisearch.cloud.google.com/home/cid/...`）** をコピーします（必要に応じて短縮URL `goo.gle/ntt-gemini` の転送先に設定します）。
4. 貸出 Chromebook（9台＋予備1台）それぞれに、`user01`〜`user10`（Qwiklabs `User 2`〜`User 11`）で事前ログインし、Chrome のタブで以下の2つを開いておきます：
   * **タブ①：Gemini Enterprise Web アプリ**（初回 Authorize 承認まで済ませておくと当日さらにスムーズです）
   * **タブ②：ハンズオン用 Codelab ページ**（プロンプトのワンクリック Copy ボタン、および『NTTグループ統合報告書』『NTTファイナンスIR資料』のダウンロードボタン・公式URLを掲載）

---

### 3. 検証・ハンズオン終了後：全リソースの一括削除（クリーンアップ手順）

Argolis 等で検証した後に作成したリソース（カスタム A2A エージェント4種、OAuth 認可設定、BigQuery データエージェント4種、Gemini Enterprise エンジン、データストア、BigQuery データセット4種、GCS バケット）をすべて削除する場合は、Cloud Shell で以下のコマンドを実行してください。

```bash
bash handson/tf/scripts/cleanup.sh
```

---

## 第2部：受講者向け ハンズオン手順書（投影スライド・Codelab 完全同期版）

### 1. 全体構成（基本45分コアシナリオ1〜3 ＋ 部門別チャートショーケース4〜6）

| パート | テーマ | 体験内容・可視化チャート |
| :--- | :--- | :--- |
| **導入 (5分)** | **Gemini Enterprise ログイン＆画面確認** | 配布されたアカウント（`user01`〜`user10`）で Gemini Enterprise Web アプリへログインし、画面構成を確認 |
| **シナリオ1 (10分)** | **【Gemini Notebook】**<br>経営戦略・業界動向のインプットと要点整理 | ① 2資料（NTTグループ統合報告書・NTTファイナンスIR資料）をアップロードし、日本語ポッドキャスト（音声概要）を生成<br>② 音声生成の待ち時間に2資料を横断して重点戦略や事業課題をQA<br>③ 完成した日本語の対談番組を試聴 |
| **シナリオ2 (12分)** | **【GE + GWS横断検索】**<br>大口取引先に関する状況把握と社内規程の確認 | 営業メール（Gmail）・審査部議論（Chat）・債権管理規程PDF（Drive）を一括横断検索し、相談経緯と経営会議付議基準・保全措置を一覧表に自動整理 |
| **シナリオ3 (18分)** | **【GE + AIエージェント】**<br>未収データ分析（請求×入金×与信）と経営会議レポート・スライド作成 | ・**時系列折れ線 / 棒グラフ**: `@請求・入金・与信分析` で月次回収率推移と要注意取引先トップ10を抽出<br>・債権保全シミュレーションと Google ドキュメント1クリック出力 ＆ **Canvas による5枚プレゼンスライド自動生成** |
| **応用① (ボーナス)** | **【コールセンター分析エージェント】**<br>入電ピーク・応対品質・顧客満足度（VOC）の可視化 | ・**散布図**: オペレーター別 AHT × 一次解決率 × CSAT 相関<br>・**円グラフ / ツリーマップ**: 問い合わせカテゴリ × 詳細理由の構成比<br>・**積み上げ棒グラフ**: 曜日 × 時間帯別の入電数・放棄呼（あふれ呼）分析 |
| **応用② (ボーナス)** | **【人事・タレント分析エージェント】**<br>残業・エンゲージメント・離職リスクの可視化 | ・**散布図**: 月平均残業時間 × エンゲージメントスコア × 離職リスク相関<br>・**複合チャート（棒＋折れ線）**: 月次退職者数（棒）＋ 平均残業時間（折れ線）<br>・**ツリーマップ**: 本部 × 職種別の人員数・人件費ボリューム構成比 |
| **応用③ (ボーナス)** | **【営業・マーケROI分析エージェント】**<br>施策投資対効果・商談フェーズ・チャネル推移の可視化＆スライド化 | ・**散布図**: キャンペーン投下費用 × 創出商談額（ROI）× 受注率の相関<br>・**円グラフ**: 商談フェーズ別のパイプライン金額構成比<br>・**積み上げ面グラフ**: チャネル種別ごとの月次獲得商談額の推移 |

---

### 2. 導入（5分）：Gemini Enterprise へのログイン

1. 手元の Chromebook を開き、配布されたアカウント（`user01`〜`user10` に対応するラボアカウント）とパスワードを確認します。
2. ブラウザで **Gemini Enterprise Web アプリ URL**（`https://goo.gle/ntt-gemini` または講師から案内されたURL）を開き、ログインします。
3. 初回ログイン時に連携承認（**[Authorize / 承認]**）が表示された場合は、クリックして許可します。

---

### 3. シナリオ1（10分）：【Gemini Notebook】経営戦略・業界動向のインプットと要点整理

#### Step 1-1：投入する2つの資料（統合報告書・IR資料）の準備

* **A. ハンズオン高速処理用 抜粋版PDF（10分枠での音声生成推奨）**
  * ① `next_group_integrated_report_2026.pdf`（統合報告書2026 主要抜粋版）
  * ② `next_finance_ir_highlights_2026.pdf`（IR決算および事業財務ハイライト資料）
* **B. 公式公開 IR 資料 URL（Webから直接参照・コピーする場合）**
  * NTTグループ統合報告書 2026（公式PDF）： `https://group.ntt/jp/ir/library/annual/pdf/integrated_report_26j.pdf`
  * NTTグループ統合報告書 ライブラリページ： `https://group.ntt/jp/ir/library/annual/`
  * NTTファイナンス 決算・連結計算書類（公式PDF）： `https://www.ntt-finance.co.jp/ir/tanshin/pdf/r7_kessan_renketsuzaimu.pdf`
  * NTTファイナンス 第41期 有価証券報告書（公式PDF）： `https://www.ntt-finance.co.jp/ir/shoken/pdf/yuukashouken_41.pdf`
  * NTTファイナンス 財務ハイライト： `https://www.ntt-finance.co.jp/ir/highlight/`

#### Step 1-2：Notebook の作成と「音声概要（Audio Overview）」の生成開始（スライド P.15〜16）

1. Gemini Enterprise 左メニューから **Gemini Notebook（または NotebookLM）** を開き、**[＋ 新規作成（New Notebook）]** をクリックして2つのPDFをアップロードします。
2. 画面右側の **Studio パネル** の **「音声概要（Audio Overview）」** のカスタマイズ（編集アイコン）をクリックし、以下の指示文を貼り付けて **[生成（Generate）]** を開始します。

```text
1. アップロードした2資料（統合報告書・IR資料）をもとに、重点戦略と事業課題を議論してください。
2. 企画・営業担当者が短時間で要点を把握できるよう、分かりやすい対談形式で解説してください。
```

#### Step 1-3：音声生成の待ち時間を使った2資料横断 QA（スライド P.17）

```text
NTTグループの中期経営戦略における金融・決済・ビリング事業の重点戦略と、現在直面している主要な事業課題（債権管理・DX推進等）を2つの資料から横断的に整理してください。
```

* 詳細引用付きプロンプト（任意）：

```text
アップロードした2つの資料（統合報告書・IR資料）を横断して分析してください。
中期経営戦略においてファイナンス・ビリング事業が果たすべき役割と、今後の重点課題（ペーパーレス化やAI活用による債権・与信リスク管理の高度化など）を3点に整理し、根拠となる資料の引用付きで教えてください。
```

#### Step 1-4：完成した日本語の音声概要を試聴（スライド P.18）

右側の Studio パネルに音声概要が完成したら、再生ボタンをクリックして日本語の対談番組を試聴します。

---

### 4. シナリオ2（12分）：【GE + GWS横断検索】大口取引先の状況把握と社内規程の確認

1. Gemini Enterprise 左メニューの **ホーム（Home / 新しいチャット）** に戻ります。
2. チャット入力欄に以下のプロンプト（スライド P.22 対応）を貼り付けて実行します。

```text
大口取引先である「東都ロジスティクス（Toto Logistics）」からの支払期日延長の相談について、営業からの相談メール（Gmail）、審査部の同種相談急増に関する議論（Chat）、および「債権管理・与信規程PDF（Drive）」を横断検索してください。その上で、以下の3点を一覧表に自動整理してください。
① 対象取引先・対象金額・相談経緯
② 審査部現場の懸念点
③ 規程上の決裁条件（経営会議付議の基準・与信枠凍結ルール・該当条文）
```

* 該当条文（第11条・第14条・第18条）および新規車載IoT回線800回線の増設可否まで詳細に指定する場合のプロンプト（任意）：

```text
大口契約先「東都ロジスティクス株式会社」からの支払期日延長（支払猶予）の相談に関して、営業部のメール報告、審査部・債権管理室のChat議論、および「通信料金等債権管理および与信運用規程」を横断検索し、以下の項目を一覧表に整理してください。
1. 対象取引先・契約回線数・月間請求額・今回の要請内容と過去の遅延経緯
2. 審査部・料金センターが懸念している法人他社（物流・建設セクター）および個人回線契約者（電話料金合算・払込票切替層）での類似傾向
3. 社内規程上の該当条文（第11条・第14条・第18条）、経営会議への付議基準、および必要な債権保全措置（新規車載IoT回線800回線の増設可否を含む）
```

---

### 5. シナリオ3（18分）：【GE + AIエージェント】未収データ分析（請求×入金×与信）と経営会議レポート作成

メインチャットの入力欄で `@` を入力し、候補から **`@請求・入金・与信分析`** を選択してプロンプトを実行します（または左メニューの「エージェント」から『請求・入金・与信分析』を選択します。初回のみ承認ボタンをクリックします）。

#### Step 3-1：全体傾向の把握（月次回収率推移の折れ線グラフ ＆ 業種×与信ランク別の未収リスク特定 / スライド P.29）

```text
@請求・入金・与信分析
「請求・入金・顧客与信」のデータを掛け合わせ、以下を可視化してください。
(1) 2026年4月〜9月の月次請求額・入金済額・未収残高・回収率の推移（折れ線グラフ）
(2) 未収リスクが拡大している「業種×与信ランク」別の未収残高・遅延傾向（棒グラフと表）
```

#### Step 3-2：明細レベルへの対話ドリルダウンと効果試算（スライド P.30）

```text
@請求・入金・与信分析
続けて明細レベルへ深掘り分析してください。
(1) 未収・遅延の主要因である要注意の大口取引先トップ10社（業種・ランク・未収額・遅延日数）を棒グラフと表で表示
(2) 高リスク先の与信枠見直しと口座振替への切替による未収リスク低減効果をシミュレーション
```

* 社内規程（第14条・第18条）に基づく与信枠20%圧縮・債権保証60%カバーを厳密に試算させる場合のプロンプト（任意）：

```text
法人_多回線一括請求の要注意顧客（ランクC1・C2）について、累積未収残高が多いトップ10社を抽出して棒グラフで比較してください。
さらに社内規程（第14条・第18条）に基づき、各社の与信限度額を20%圧縮した場合の新与信枠と、未収残高の60%を債権保証で保全カバーした場合のリスク低減額および残余リスク額を試算してください。
```

#### Step 3-3：経営会議レポートの作成 ＆ Google ドキュメント / Canvas スライドへ1クリック出力（スライド P.31〜33）

1. 同じチャットスレッドで以下のプロンプトを入力し、経営会議向け対策レポートを作成して **[Google ドキュメントにエクスポート]** をクリックします（推奨タイトル：`[社内報告] 大口契約先の支払条件変更決裁および全社ビリング債権リスク対策レポート`）。

```text
これまでの社内規程・メール確認結果と、@請求・入金・与信分析 の分析結果（回収率推移・要注意トップ10社・保全試算）を統合し、経営会議向けの『大口契約先の支払条件変更決裁および全社債権リスク対策レポート』を作成してください。
```

2. 続けて、画面を切り替えずに同じチャット入力欄で **[ツール（＋）] → [Canvas]** を選択し、以下のプロンプトを送信して5枚構成のプレゼンスライドを自動生成します。

```text
今の分析結果をもとに、来週の経営会議で発表するための報告用プレゼンテーションスライドを5枚構成（1.エグゼクティブサマリ、2.月次回収率の推移と課題、3.要注意法人トップ10社の未収状況、4.与信枠見直し・債権保全によるリスク低減シミュレーション、5.今後のアクションプラン）で作成してください。
```

3. 右側の Canvas ペインに生成されたスライドを確認し、右上の **[エクスポート] → [Google スライドにエクスポート]** で Google スライドとして保存します。

---

### 6. 応用ショーケース①：【コールセンター分析】エージェントで多彩なチャートを体験

#### ① 散布図（Scatter Chart）：オペレーター別 AHT × 一次解決率（FCR）× CSAT の相関分析

```text
@コールセンター分析
オペレーター別の「平均処理時間（avg_handle_time_sec）」と「一次解決率（first_call_resolution_rate）」の相関関係を散布図（Scatter Chart）で描画してください。あわせて、処理時間は短い（早切りしている）のに一次解決率や顧客満足度（avg_csat_score）が著しく低い要注意オペレーターを特定してください。
```

#### ② 円グラフ / ツリーマップ：問い合わせカテゴリ＆詳細理由の構成比

```text
@コールセンター分析
入電ログ（call_logs）から、問い合わせ大分類（inquiry_category）ごとの入電件数シェアを円グラフ（Pie Chart）で可視化してください。さらに、大分類×詳細理由（inquiry_sub_reason）の2階層のボリューム構成比をツリーマップ（Treemap）または内訳グラフで表示してください。
```

#### ③ 積み上げ棒グラフ：曜日 × 時間帯別の入電集中と放棄呼（あふれ呼）の特定

```text
@コールセンター分析
曜日（day_of_week）および時間帯（hour_slot）ごとの入電件数と放棄呼（is_abandoned=1）の発生状況を、時間帯別の積み上げ棒グラフで可視化し、どの曜日・時間帯にオペレーター増員が必要か提案してください。
```

---

### 7. 応用ショーケース②：【人事・タレント分析】エージェントで多彩なチャートを体験

#### ① 散布図（Scatter Chart）：月平均残業時間 × エンゲージメントスコアの負の相関

```text
@人事・タレント分析
社員マスタ（employees）のデータから、「直近6ヶ月平均残業時間（avg_overtime_hours_6m）」と「エンゲージメント総合スコア（engagement_score）」の関係を散布図（Scatter Chart）でプロットしてください。残業が何時間を超えるとエンゲージメントが急落し離職リスク（High_要ケア）が急増しているか、本部別の傾向とあわせて分析してください。
```

#### ② 複合チャート（Combo Chart：棒＋折れ線）：月次の退職人数と平均残業時間の推移比較

```text
@人事・タレント分析
月次勤怠データ（attendance_monthly）を集計し、2026年4月〜9月の月別の「退職発生人数（is_retiredの合計：棒グラフ）」と「全社平均残業時間（overtime_hoursの平均：折れ線グラフ）」を1つの複合チャート（Combo Chart）で描画して、残業増加と退職増加の連動性を教えてください。
```

#### ③ ツリーマップ（Treemap）：本部 × 職種別の人員数・人件費ボリューム構成比

```text
@人事・タレント分析
本部（division_name）× 職種（job_role）ごとの在籍人数と人件費総額（annual_salary_jpyの合計）を集計し、ツリーマップ（Treemap）で組織の人員・コスト構造を可視化してください。
```

---

### 8. 応用ショーケース③：【営業・マーケROI分析】エージェントで多彩なチャートを体験

#### ① 散布図（Scatter Chart）：キャンペーン投下費用 × 創出商談パイプライン金額（ROI）の相関

```text
@営業・マーケROI分析
マーケティング施策（marketing_campaigns）について、X軸に「投下費用（spend_jpy）」、Y軸に「創出商談金額（pipeline_generated_jpy）」をとった散布図（Scatter Chart）を描画してください。高コストなのにROIが低い施策と、低コストで高い商談金額・受注率（win_rate_pct）を生んでいる高効率チャネルを特定してください。
```

#### ② 円グラフ / ドーナツチャート（Pie Chart）：商談フェーズ別のパイプライン金額シェア

```text
@営業・マーケROI分析
商談パイプライン（sales_opportunities）について、現在の商談フェーズ（stage_name：5段階）ごとの商談金額（deal_amount_jpy）の構成比を円グラフ（Pie Chart）で描画し、フェーズ別の件数・期待金額（weighted_amount_jpy）とあわせて要約してください。
```

#### ③ 積み上げ面グラフ（Stacked Area Chart）：チャネル種別ごとの月次創出商談額の推移

```text
@営業・マーケROI分析
2026年4月〜9月の商談発生月（created_month）ごとに、獲得チャネル種別（channel_category）別の商談金額（deal_amount_jpy）の推移を積み上げ面グラフ（Stacked Area Chart）で描画し、直近で急成長しているチャネルを教えてください。
```
