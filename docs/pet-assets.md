# A・Bのキャラクター素材

2026年10月20日。ユーザーが選定したA · CLASSICとB · LOW RUNの比較画像を入力に、組み込みのimage_genでそれぞれ4コマの透過スプライトシートを生成した。CLI／外部APIキーは使っていない。

- `Sources/MenuPup/Resources/Pets/a-classic.png`：A · Classic、ずんぐりした体。
- `Sources/MenuPup/Resources/Pets/b-low-run.png`：B · Low Run、頭と背中が低くつながる横長の体。

これらはアプリの製品素材であり、検証スクリーンショットではない。SwiftPMリソースとしてバンドルし、起動時に4分割・透明余白の除外を行う。同一キャラクター内で縮尺と足元の基準をそろえ、一度描画したフレームを再利用する。PNGの縦横比を維持し、高さ22ptの表示枠で使用する。

## 最終プロンプト

次の共通プロンプトの`DIRECTION`に各方向の文を挿入した。入力画像は、それぞれ採用済みの比較案のみ。`transparent_background=true`。

> Edit target: supplied Annoying Dog character design sheet. Extract its selected character design faithfully into a production sprite sheet. DIRECTION Preserve the character's face, white silhouette, stubby legs, short ears and proportions. Produce ONLY FOUR running animation frames in an exactly aligned 2 by 2 equal-cell square atlas, reading order top-left, top-right, bottom-left, bottom-right. EACH FRAME MUST BE THE SAME CHARACTER AND SCALE. Head and body stay in precisely the same position relative to the cell, animate only four short legs through contact, gather, opposite contact, gather poses with at most one logical pixel bob. Coarse authentic pixel art, crisp square pixels; enlarged grid approximately 28 by 22 logical pixels per character, no smoothing. Thin black pixel outline completely enclosing white body, black facial details. Transparent background with genuine alpha. Entire frame transparent except dog. Every cell has identical transparent margins of about 8 percent; center each dog within its cell. No labels, no titles, no swatches, no sheet divisions, no shadows, no gray background, no extra characters. This will be rendered at only 22pt high in a macOS menu bar, so the face must remain big and readable.

AのDIRECTION：

> A CLASSIC: compact, stout, squarish fluffy body, matching the large dog and four run-cycle images in the supplied reference. Large head merged into the plump torso, exactly that face and curled tail. Body width to height about 1.35.

BのDIRECTION：

> B LOW RUN: low, plump horizontal loaf body, matching the large dog and four run-cycle images in the supplied reference. Head flush with back, no raised neck, exactly that cheerful face, short ears and curled tail. Body width to height about 1.9.
