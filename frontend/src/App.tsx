// type キーワードを追加して TS1484 を解消
import { useState, useEffect, useMemo, type ComponentProps } from 'react';
import {
  FluentProvider,
  webLightTheme,
  Title1,
  Subtitle1,
  Card,
  Table,
  TableHeader,
  TableRow,
  TableHeaderCell,
  TableBody,
  TableCell,
  TableCellLayout,
  Spinner,
  Button,
  Dialog,
  DialogTrigger,
  DialogSurface,
  DialogTitle,
  DialogBody,
  DialogContent,
  SearchBox,
  Dropdown,
  Option,
} from "@fluentui/react-components";

// データの型定義
interface WordItem {
  word: string;
  phonetic: string;
  definition_fr: string;
  meaning_jp: string;
  file_key: string;
  updated_at: string;
}

type SortKey = 'alphabetical' | 'newest';

export default function App() {
  const [items, setItems] = useState<WordItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // 検索・ソート用の状態
  const [searchQuery, setSearchQuery] = useState("");
  const [sortKey, setSortKey] = useState<SortKey>('newest');

  const API_URL = "https://sherlock.lesure.net/api/v1/words/all";

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);
        const response = await fetch(API_URL);
        if (!response.ok) throw new Error("API接続に失敗しました");
        const data: WordItem[] = await response.json();
        setItems(data);
      } catch (err) {
        setError("データの取得に失敗しました。");
        console.error(err);
      } finally {
        setLoading(false);
      }
    };
    fetchData();
  }, []);

  // フィルタリングとソートを適用したリストを計算
  const filteredAndSortedItems = useMemo(() => {
    let result = [...items];

    if (searchQuery) {
      const q = searchQuery.toLowerCase();
      result = result.filter(item => 
        item.word.toLowerCase().includes(q) || 
        item.meaning_jp.toLowerCase().includes(q)
      );
    }

    if (sortKey === 'alphabetical') {
      result.sort((a, b) => a.word.localeCompare(b.word));
    } else if (sortKey === 'newest') {
      result.sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime());
    }

    return result;
  }, [items, searchQuery, sortKey]);

  // Dropdownから型を直接推論させることでエクスポートエラーを回避
  const onSortChange: ComponentProps<typeof Dropdown>["onOptionSelect"] = (_e, data) => {
    if (data.optionValue) {
      setSortKey(data.optionValue as SortKey);
    }
  };

  return (
    <FluentProvider theme={webLightTheme}>
      <div style={{ padding: '24px 40px', maxWidth: '1000px', margin: '0 auto', background: '#fafafa', minHeight: '100vh' }}>
        
        <header style={{ marginBottom: '32px' }}>
          <Title1 as="h1">Sherlock</Title1>
          <Subtitle1 block style={{ color: '#605e5c' }}>Lexique Français</Subtitle1>
          
          {/* 操作エリア */}
          <div style={{ display: 'flex', gap: '12px', marginTop: '24px', alignItems: 'center' }}>
            <SearchBox 
              placeholder="単語または意味で検索..." 
              style={{ flexGrow: 1 }}
              value={searchQuery}
              onChange={(_, data) => setSearchQuery(data.value)}
            />
            <Dropdown 
              placeholder="並び替え" 
              selectedOptions={[sortKey]}
              onOptionSelect={onSortChange}
              style={{ minWidth: '160px' }}
            >
              <Option value="newest">新しい順</Option>
              <Option value="alphabetical">アルファベット順</Option>
            </Dropdown>
          </div>
        </header>

        <Card style={{ padding: 0, border: '1px solid #e1dfdd', borderRadius: '8px', overflow: 'hidden' }}>
          {loading ? (
            <div style={{ padding: '60px', textAlign: 'center' }}><Spinner label="S3から知を同期中..." /></div>
          ) : error ? (
            <div style={{ padding: '40px', color: '#d13438' }}>{error}</div>
          ) : (
            <Table size="small">
              <TableHeader>
                <TableRow>
                  <TableHeaderCell style={headerStyle}>Mot</TableHeaderCell>
                  <TableHeaderCell style={headerStyle}>Signification (JA)</TableHeaderCell>
                  <TableHeaderCell style={{ ...headerStyle, textAlign: 'center', width: '80px' }}>Action</TableHeaderCell>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredAndSortedItems.map((item, index) => (
                  <TableRow key={`${item.word}-${index}`} style={{ backgroundColor: '#fff' }}>
                    <TableCell>
                      <TableCellLayout>
                        <strong style={{ color: '#0078d4', fontSize: '1rem' }}>{item.word}</strong>
                        {item.phonetic && item.phonetic !== "N/A" && <span style={phoneticStyle}>{item.phonetic}</span>}
                      </TableCellLayout>
                    </TableCell>
                    <TableCell>{item.meaning_jp}</TableCell>
                    <TableCell style={{ textAlign: 'center' }}>
                      <Dialog>
                        <DialogTrigger disableButtonEnhancement>
                          <Button appearance="subtle" size="small">詳細</Button>
                        </DialogTrigger>
                        <DialogSurface>
                          <DialogBody>
                            <DialogTitle>{item.word}</DialogTitle>
                            <DialogContent>
                              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', marginTop: '10px' }}>
                                <div>
                                  <div style={labelStyle}>Signification (JA)</div>
                                  <p style={{ fontSize: '1.2rem', margin: '4px 0 0 0', fontWeight: 500 }}>{item.meaning_jp}</p>
                                </div>
                                <div>
                                  <div style={labelStyle}>Définition (FR)</div>
                                  <p style={frDefStyle}>{item.definition_fr}</p>
                                </div>
                                <p style={footerDateStyle}>Dernière mise à jour: {new Date(item.updated_at).toLocaleString('ja-JP')}</p>
                              </div>
                            </DialogContent>
                          </DialogBody>
                        </DialogSurface>
                      </Dialog>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </Card>

        <footer style={{ marginTop: '20px', color: '#8a8886', fontSize: '0.8rem', textAlign: 'right' }}>
          {filteredAndSortedItems.length} items found / {items.length} total
        </footer>
      </div>
    </FluentProvider>
  );
}

// スタイル定数
const headerStyle: React.CSSProperties = { padding: '12px 20px', fontWeight: 600, color: '#605e5c', background: '#f0f0f0' };
const phoneticStyle: React.CSSProperties = { marginLeft: '8px', color: '#8a8886', fontSize: '0.85rem', fontStyle: 'italic' };
const labelStyle: React.CSSProperties = { fontSize: '0.7rem', fontWeight: 700, color: '#0078d4', textTransform: 'uppercase', letterSpacing: '0.5px' };
const frDefStyle: React.CSSProperties = { fontSize: '1rem', lineHeight: '1.6', borderLeft: '4px solid #0078d4', paddingLeft: '16px', fontStyle: 'italic', color: '#323130', whiteSpace: 'pre-wrap', marginTop: '8px' };
const footerDateStyle: React.CSSProperties = { marginTop: '20px', fontSize: '0.75rem', color: '#a19f9d', textAlign: 'right', borderTop: '1px solid #f3f2f1', paddingTop: '12px' };