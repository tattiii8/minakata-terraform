#!/bin/bash

set -e

PROJECT_ROOT=$(pwd)
FRONTEND_DIR="$PROJECT_ROOT/frontend"

echo "------------------------------------------------"
echo "  🛠️ Agent Sherlock: Fluent UI Installer"
echo "------------------------------------------------"

# 1. frontend ディレクトリの存在確認
if [ ! -d "$FRONTEND_DIR" ]; then
    echo "❌ エラー: frontend ディレクトリが見つかりません。"
    echo "先に ./react_init.sh を実行してください。"
    exit 1
fi

cd "$FRONTEND_DIR"

# 2. パッケージのインストール
echo "📚 Fluent UI (Components & Icons) をインストール中..."
npm install @fluentui/react-components @fluentui/react-icons --save

# 3. インストール検証
echo "🔍 装備チェック中..."
if [ -f "node_modules/@fluentui/react-components/package.json" ]; then
    echo "✅ Fluent UI のインストールを確認しました。"
else
    echo "❌ インストールに失敗しました。npm のエラーログを確認してください。"
    exit 1
fi

# 4. App.tsx を Fluent UI 仕様に強制上書き
echo "🎨 App.tsx を Fluent UI 仕様にアップグレード中..."
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
      <div style={{ padding: '40px', maxWidth: '600px', margin: '0 auto' }}>
        <Card>
          <CardHeader
            header={<Title1>🕵️‍♂️ Agent Sherlock</Title1>}
            description={<Subtitle2>Mission: Vocabulaire Français</Subtitle2>}
          />
          <Divider />
          <div style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: '15px' }}>
            <p>L'installation de Fluent UI est réussie. (UIの導入に成功しました)</p>
            <Button 
              appearance="primary" 
              icon={<BookSearch24Regular />}
              onClick={() => alert("エージェントがデータを読み取ります...")}
            >
              調査ログを表示
            </Button>
          </div>
        </Card>
      </div>
    </FluentProvider>
  );
}
EOF

echo "------------------------------------------------"
echo "✨ Fluent UI のセットアップが完了しました！"
echo "cd frontend && npm run dev で確認してください。"