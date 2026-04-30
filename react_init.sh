#!/bin/bash

set -e

PROJECT_ROOT=$(pwd)
FRONTEND_DIR="$PROJECT_ROOT/frontend"

echo "------------------------------------------------"
echo "  🕵️‍♂️ Agent Sherlock: Frontend Initializer (v6)"
echo "------------------------------------------------"

# 1. 既存ディレクトリのリセット
if [ -d "$FRONTEND_DIR" ]; then
    echo "🧹 クリーンアップ中..."
    rm -rf "$FRONTEND_DIR"
fi

# 2. Vite プロジェクトの生成
# 自動起動を防ぐため、npm create vite を実行するだけで、その後の npm install はスクリプトで制御します
echo "📦 Vite プロジェクトの構造を生成中..."
# ここで --yes を使わず、引数だけで構成を指定することで自動起動を回避します
npm create vite@latest frontend -- --template react-ts

cd "$FRONTEND_DIR"

# 3. 依存関係のインストール（ここが本番）
echo "📚 ライブラリをインストール中 (これには少し時間がかかります)..."
# 開発サーバーが立ち上がらないよう、install のみ実行
npm install --no-fund --no-audit

echo "📚 Fluent UI を追加中..."
npm install @fluentui/react-components @fluentui/react-icons --save

# 4. インストール検証
if [ -f "node_modules/@fluentui/react-components/package.json" ]; then
    echo "✅ Fluent UI のインストールを確認しました。"
else
    echo "❌ インストール失敗。手動で 'npm install' を試してください。"
    exit 1
fi

# 5. App.tsx の作成（エージェント仕様）
echo "🎨 App.tsx を作成中..."
cat <<EOF > src/App.tsx
import { 
  FluentProvider, 
  webLightTheme, 
  Title1, 
  Subtitle2, 
  Button, 
  Card, 
  CardHeader,
  Divider
} from "@fluentui/react-components";
import { BookSearch24Regular } from "@fluentui/react-icons";

export default function App() {
  return (
    <FluentProvider theme={webLightTheme}>
      <div style={{ padding: '40px', maxWidth: '800px', margin: '0 auto' }}>
        <Card>
          <CardHeader
            header={<Title1>🕵️‍♂️ Agent Sherlock</Title1>}
            description={<Subtitle2>Humanities & Language Lab</Subtitle2>}
          />
          <Divider />
          <div style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: '15px' }}>
            <p>L'Agent est prêt. 全自動セットアップに成功しました。</p>
            <Button 
              appearance="primary" 
              icon={<BookSearch24Regular />}
              onClick={() => alert("調査データにアクセス中...")}
            >
              単語ログを表示
            </Button>
          </div>
        </Card>
      </div>
    </FluentProvider>
  );
}
EOF

# 6. vite.config.ts の修正
echo "⚙️ vite.config.ts を修正中..."
cat <<EOF > vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: './',
})
EOF

echo "------------------------------------------------"
echo "✨ 完了！スクリプトは最後まで走り切りました。"
echo "------------------------------------------------"
echo "以下のコマンドでエージェントを起動してください："
echo "cd frontend"
echo "npm run dev"