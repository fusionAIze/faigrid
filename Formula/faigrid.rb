class Faigrid < Formula
  desc "fusionAIze Grid — AI infrastructure orchestrator for multi-node setups"
  homepage "https://github.com/fusionAIze/faigrid"
  url "https://github.com/fusionAIze/faigrid/archive/refs/tags/v1.6.0.tar.gz"
  sha256 "c9fb036ccbe3294022326c12ab70d1683be17b3a1d8381fd75b4d51a2a2d6257"
  license "Apache-2.0"
  head "https://github.com/fusionAIze/faigrid.git", branch: "main"

  depends_on "bash"
  depends_on "rsync"

  def install
    libexec.install Dir["*"]

    (bin/"faigrid").write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
      exec "#{libexec}/install.sh" "$@"
    SH

    # Expose workbench control directly
    (bin/"faigrid-workbench").write <<~SH
      #!/usr/bin/env bash
      set -euo pipefail
      exec "#{libexec}/core/workbench/scripts/control.sh" "$@"
    SH
  end

  def post_install
    (var/"log/faigrid").mkpath
  end

  test do
    assert_predicate bin/"faigrid", :executable?
    assert_predicate libexec/"install.sh", :exist?
    assert_predicate libexec/"core/workbench/scripts/control.sh", :exist?
  end
end
