# Template contract verification

実際の GCP 操作を行わず、テンプレートに費用安全策が残っていることを確認する。

実行:

    ./scripts/verify-template-contract.sh

確認対象:

- Cloud Run はイメージ指定でデプロイし、source deploy を使わない。
- region はテンプレート変数で明示される。
- min instances は0、CPUとメモリは明示的な既定値である。
- 常時CPU、startup CPU boost、session affinity を含めない。

この検査はCIへ追加する前でもローカルで安全に実行できる。
