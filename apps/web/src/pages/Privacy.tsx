import { PUBLIC_AI_ENABLED } from '../lib/deployment'

const SITE_ROOT = import.meta.env.BASE_URL

export function Privacy() {
  return (
    <main className="landing-page privacy-page">
      <nav className="landing-nav" aria-label="主导航">
        <a className="landing-brand" href={SITE_ROOT} aria-label="Milo 米洛首页">
          <img className="landing-brand-logo" src={`${SITE_ROOT}favicon.png`} alt="" width="36" height="36" />
          <span><strong>Milo</strong><em>米洛</em></span>
        </a>
        <a className="landing-nav-cta" href={`${SITE_ROOT}app`}>打开 Web 端 <span aria-hidden="true">↗</span></a>
      </nav>

      <article className="privacy-content">
        <header className="privacy-heading">
          <p className="landing-kicker"><span /> 由你决定，向谁表达</p>
          <h1>隐私说明</h1>
          <p>这份说明适用于 Milo 网页版，帮助你了解记录放在哪里，以及文字如何被使用。</p>
          <span className="privacy-updated">更新于 2026 年 9 月 23 日</span>
        </header>

        <section aria-labelledby="privacy-local-title">
          <span className="privacy-section-number">01</span>
          <div>
            <h2 id="privacy-local-title">你的记录，保存在当前浏览器</h2>
            <p>Milo 网页版无需注册或登录账号。保存的日记、心情与回忆使用浏览器本地存储（localStorage），不会自动上传为云端日记。</p>
            <p>换设备、换浏览器或换访问地址，都不会自动同步原有记录。清除此网站的浏览器数据，可能让这些记录一同消失；请先保存想留下的内容。</p>
          </div>
        </section>

        <section aria-labelledby="privacy-ai-title">
          <span className="privacy-section-number">02</span>
          <div>
            {PUBLIC_AI_ENABLED ? <>
            <h2 id="privacy-ai-title">开启 AI 前，先由你选择</h2>
            <p>进入回忆对话时，你可以选择本地引导，也可以选择“同意并开启 AI”。这份选择只用于本次回忆，不会默认替以后每一次对话开启 AI。</p>
            <p>开启后，本次心情、时间线索，以及你输入的对话，会经过 Milo 自有的华为云 AI 网关发送给 MiniMax，用于生成简短提问、回应和整理日记。这些内容会离开浏览器，由 AI 服务处理。</p>
            <p>不开启 AI，仍可使用本地情绪选择、引导、日记和回忆功能。</p>
            </> : <>
            <h2 id="privacy-ai-title">在本地，慢慢说</h2>
            <p>当前网页版使用本地的简短提示陪你记录，没有开启在线 AI。你输入的情绪、对话和日记不会发送给 AI 服务。</p>
            <p>网站由 Vercel 托管，加载网页时会产生提供网络服务所需的请求信息；这些请求不包含你的日记正文。</p>
            </>}
          </div>
        </section>

        <section aria-labelledby="privacy-sharing-title">
          <span className="privacy-section-number">03</span>
          <div>
            <h2 id="privacy-sharing-title">没有公开社区，也没有广告追踪 SDK</h2>
            <p>Milo 网页版没有用户社区，也未接入广告追踪 SDK。日记不会自动公开。是否导出分享卡片、把内容分享给别人，由你自行决定。</p>
          </div>
        </section>

        <a className="landing-inline-link privacy-home-link" href={SITE_ROOT}>回到 Milo 官网 <span aria-hidden="true">↗</span></a>
      </article>

      <footer className="landing-footer">
        <span>© {new Date().getFullYear()} Milo-米洛</span>
        <span>让情绪有地方落下</span>
      </footer>
    </main>
  )
}
