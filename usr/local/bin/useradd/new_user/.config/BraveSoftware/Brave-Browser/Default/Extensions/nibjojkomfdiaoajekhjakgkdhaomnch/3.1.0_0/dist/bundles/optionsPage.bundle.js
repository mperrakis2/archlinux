(()=>{"use strict";var e,t={8325:(e,t,i)=>{Object.defineProperty(t,"__esModule",{value:!0}),t.addRuleToDynamicRuleSetGenerator=t.generateAddRule=t.cleanupRules=t.getExtraInfoSpec=t.escapeURLRegex=t.isLocalHost=t.notifyDeleteRule=t.notifyOptionChange=t.supportsDeclarativeNetRequest=t.defaultNSRegexStr=t.RULE_REGEX_ENDING=t.MAX_RETRIES_TO_UPDATE_TAB=t.GLOBAL_STATE_OPTION_CHANGE=t.DELETE_RULE_REQUEST_SUCCESS=t.DELETE_RULE_REQUEST=t.DEFAULT_NAMESPACES=void 0;const n=i(655),a=n.__importDefault(i(1227)),s=i(2422),o=n.__importDefault(i(3150)),l=i(5489),r=i(2283),d=i(3675),c=(0,a.default)("ipfs-companion:redirect-handler:blockOrObserve");c.error=(0,a.default)("ipfs-companion:redirect-handler:blockOrObserve:error"),t.DEFAULT_NAMESPACES=new Set(["ipfs","ipns"]),t.DELETE_RULE_REQUEST="DELETE_RULE_REQUEST",t.DELETE_RULE_REQUEST_SUCCESS="DELETE_RULE_REQUEST_SUCCESS",t.GLOBAL_STATE_OPTION_CHANGE="GLOBAL_STATE_OPTION_CHANGE",t.MAX_RETRIES_TO_UPDATE_TAB=5,t.RULE_REGEX_ENDING="((?:[^\\.]|$).*)$",t.defaultNSRegexStr=`(${[...t.DEFAULT_NAMESPACES].join("|")})`;async function p(e,i){if((0,t.supportsDeclarativeNetRequest)()){const t={type:e,value:i};await o.default.runtime.sendMessage(t)}}t.supportsDeclarativeNetRequest=()=>o.default.declarativeNetRequest?.MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES>0,t.notifyOptionChange=async function(){return c("notifyOptionChange"),await p(t.GLOBAL_STATE_OPTION_CHANGE)},t.notifyDeleteRule=async function(e){return await p(t.DELETE_RULE_REQUEST,e)};const u=new Map,g=[{originUrl:"http://127.0.0.1",redirectUrl:"http://localhost",getPort:({gwURLString:e})=>new URL(e).port},{originUrl:"http://[::1]",redirectUrl:"http://localhost",getPort:({gwURLString:e})=>new URL(e).port},{originUrl:"http://localhost",redirectUrl:"http://127.0.0.1",getPort:({apiURL:e})=>new URL(e).port}];function f(e){return e.startsWith("http://127.0.0.1")||e.startsWith("http://localhost")||e.startsWith("http://[::1]")}function b(e){return e.replace(/([:\/\?#\[\]@!$&'\(\ )\*\+,;=\-_\.~])/g,"\\$1")}function m(e){if(void 0!==e.condition.regexFilter){const t=u.get(e.condition.regexFilter);if(void 0!==t)return t.id!==e.id||t.regexSubstitution!==e.action.redirect?.regexSubstitution}return!0}async function h(e=!1){if(!(0,t.supportsDeclarativeNetRequest)())return;const i=(await o.default.declarativeNetRequest.getDynamicRules()).map((({id:e})=>e));await o.default.declarativeNetRequest.updateDynamicRules({addRules:[],removeRuleIds:i}),e&&u.clear()}async function v(e){const i=await o.default.declarativeNetRequest.getDynamicRules(),n=[],a=[];for(const e of i)"redirect"===e.action.type&&void 0!==e.condition.regexFilter&&void 0!==e.action.redirect?.regexSubstitution&&(m(e)?(a.push(e.id),u.delete(e.condition.regexFilter)):u.set(e.condition.regexFilter,{id:e.id,regexSubstitution:e.action.redirect?.regexSubstitution}));if(e.active){if(0===i.length)for(const[e,{regexSubstitution:t,id:i}]of u.entries())n.push(_(i,e,t));for(const{originUrl:i,redirectUrl:a,getPort:s}of g){const o=s(e),l=`^${b(`${i}:${o}`)}\\/${t.defaultNSRegexStr}\\/${t.RULE_REGEX_ENDING}`,r=`${a}:${o}/\\1/\\2`;u.has(l)||n.push(y(l,r))}await o.default.declarativeNetRequest.updateDynamicRules({addRules:n,removeRuleIds:a})}else await h()}function y(e,t,i=[]){const n=(0,s.fastHashCode)(`${e}:${t}:${i.join(":")}`,{forcePositive:!0});return u.set(e,{id:n,regexSubstitution:t}),_(n,e,t,i)}function _(e,t,i,n=[]){return{id:e,priority:1,action:{type:"redirect",redirect:{regexSubstitution:i}},condition:{regexFilter:t,excludedInitiatorDomains:n,resourceTypes:["csp_report","font","image","main_frame","media","object","other","ping","script","stylesheet","sub_frame","webbundle","xmlhttprequest"]}}}t.isLocalHost=f,t.escapeURLRegex=b,t.getExtraInfoSpec=function(e=[]){return(0,t.supportsDeclarativeNetRequest)()?e:["blocking",...e]},t.cleanupRules=h,t.generateAddRule=_,t.addRuleToDynamicRuleSetGenerator=function(e){var i;async function n({originUrl:e,redirectUrl:i},a=1){if(a>t.MAX_RETRIES_TO_UPDATE_TAB)return;const s=await o.default.tabs.query({url:`${e}*`});0===s.length?(await new Promise((e=>setTimeout(e,100))),await n({originUrl:e,redirectUrl:i},a+1)):await Promise.all(s.map((async e=>await o.default.tabs.update(e.id,{url:i}))))}return i={[t.GLOBAL_STATE_OPTION_CHANGE]:async()=>{c("GLOBAL_STATE_OPTION_CHANGE"),await h(!0),await v(e())},[t.DELETE_RULE_REQUEST]:async e=>{null!=e?(await async function(e){const[{condition:{regexFilter:t}}]=await o.default.declarativeNetRequest.getDynamicRules({ruleIds:[e]});u.delete(t),await o.default.declarativeNetRequest.updateDynamicRules({addRules:[],removeRuleIds:[e]})}(e),await o.default.runtime.sendMessage({type:t.DELETE_RULE_REQUEST_SUCCESS})):await h(!0)}},o.default.runtime.onMessage.addListener((async e=>{const{type:t,value:n}=e;t in i&&await i[t](n)})),async function({originUrl:t,redirectUrl:i}){const a=e(),s=t===i,c=f(t)&&f(i),p=t.includes(a.gwURL.host)&&!i.includes("recovery");if(s||p||c)return;n({originUrl:t,redirectUrl:i});const{regexSubstitution:g,regexFilter:b}=function({originUrl:e,redirectUrl:t}){const i=[d.SubdomainRedirectRegexFilter,r.NamespaceRedirectRegexFilter,l.CommonPatternRedirectRegexFilter];for(const n of i){const i=new n({originUrl:e,redirectUrl:t});if(i.canHandle)return i.filter}return new l.CommonPatternRedirectRegexFilter({originUrl:e,redirectUrl:t}).filter}({originUrl:t,redirectUrl:i}),m=u.get(b);if(void 0===m||m.regexSubstitution!==g){const e=[];void 0!==m&&(e.push(m.id),u.delete(b)),await o.default.declarativeNetRequest.updateDynamicRules({addRules:[y(b,g)],removeRuleIds:e})}await v(a)}}},1536:(e,t,i)=>{i.r(t),i.d(t,{brave:()=>c,braveNodeType:()=>m,destroy:()=>u,init:()=>p,releaseBraveEndpoint:()=>y,useBraveEndpoint:()=>v});var n=i(2894),a=i(1227),s=i(6125),o=i(5700),l=i(8583);const r=a("ipfs-companion:client:brave");r.error=a("ipfs-companion:client:brave:error");const d=(e,t)=>(0,n.Z)(e,{interval:l.es,timeout:t||1/0}),c="object"==typeof chrome&&"object"==typeof chrome.ipfs&&"function"==typeof chrome.ipfs.getIPFSEnabled&&"function"==typeof chrome.ipfs.getResolveMethodType&&"function"==typeof chrome.ipfs.launch&&"function"==typeof chrome.ipfs.shutdown&&"function"==typeof chrome.ipfs.getExecutableAvailable&&"function"==typeof chrome.ipfs.getConfig?Object.freeze({getIPFSEnabled:async()=>Boolean(await h(chrome.ipfs.getIPFSEnabled)),getResolveMethodType:async()=>String(await h(chrome.ipfs.getResolveMethodType)),getConfig:async()=>await h(chrome.ipfs.getConfig),getExecutableAvailable:async()=>Boolean(await h(chrome.ipfs.getExecutableAvailable)),launch:async()=>Boolean(await h(chrome.ipfs.launch)),shutdown:async()=>Boolean(await h(chrome.ipfs.shutdown))}):void 0;async function p(e,t){return r("ensuring Brave Settings are correct"),await async function(e,t){let i=await t.getResolveMethodType();r(`brave.resolveMethodType is '${i}'`),"ask"===i&&(await e.tabs.create({url:g}),r("waiting for user to make a decision how IPFS resources should be resolved"),await d((async()=>(i=await t.getResolveMethodType(),i&&"ask"!==i))),r(`user set resolveMethodType to '${i}'`),"local"===i&&(r("waiting while Brave downloads IPFS executable.."),await d((()=>t.getExecutableAvailable())),r("waiting while Brave creates repo and config via ipfs init.."),await d((async()=>void 0!==await t.getConfig()))));if("local"!==i)throw await e.storage.local.set({active:!1}),await w(e,g),await w(e,f),await e.tabs.create({url:b}),new Error('"Method to resolve IPFS resources" in Brave settings should be "Local node"');r("waiting while brave.launch() starts ipfs daemon.."),await d((()=>t.launch())),r("brave.launch() finished"),await v(e),setTimeout((()=>async function(e){try{const{customGatewayUrl:t}=await e.storage.local.get("customGatewayUrl");await d((async()=>{try{return await fetch(`${t}/ipfs/bafkqae2xmvwgg33nmuqhi3zajfiemuzahiwss`).then((e=>e.ok))}catch(e){return!1}})),r("[activation ui cleanup] Brave gateway is up, cleaning up");const i=e.runtime.getURL(l.O_),n=e.runtime.getURL(l.hO);for(const t of await e.tabs.query({}))try{t.url!==g&&t.url!==f||await e.tabs.remove(t.id),t.url===i&&(await e.tabs.reload(t.id),await e.tabs.update(t.id,{active:!0})),t.url===n&&await e.tabs.update(t.id,{active:!0})}catch(e){r.error("[activation ui cleanup] unexpected error, but safe to ignore",e);continue}r("[activation ui cleanup] done")}catch(e){r.error("[activation ui cleanup] failed to cleanup ephemeral UI tab",e)}}(e)),l.es)}(e,c),r('delegating API client init to "external" backend pointed at node managed by Brave'),s.init(e,t)}async function u(e){r("shuting down node managed by Brave");return"local"===await c.getResolveMethodType()&&(r("waiting for brave.shutdown() to finish"),await d((()=>c.shutdown())),r("brave.shutdown() done")),r('delegating API client destroy to "external" backend pointed at node managed by Brave'),s.destroy(e)}const g="ipfs://bafkqae2xmvwgg33nmuqhi3zajfiemuzahiwss/",f="https://bafkqae2xmvwgg33nmuqhi3zajfiemuzahiwss.ipfs.dweb.link/",b="brave://settings/extensions",m="external:brave";const h=e=>new Promise(((t,i)=>{try{e===chrome.ipfs.getConfig&&e(((e,i)=>t(e&&i?JSON.parse(i):void 0))),e((e=>t(e)))}catch(e){r.error("unexpected error during promisifyBraveCheck",e),i(e)}}));async function v(e){const t=await c.getConfig();if(void 0===t)return void r.error("useBraveEndpoint: IPFS_PATH/config is missing, unable to use endpoint from Brave at this time, will try later");const{externalNodeConfig:i,customGatewayUrl:n,ipfsApiUrl:a}=await e.storage.local.get(["customGatewayUrl","ipfsApiUrl","externalNodeConfig"]),s=_(t.Addresses.API),o=_(t.Addresses.Gateway);s!==a||o!==n?(r(`useBraveEndpoint: setting api=${s}, gw=${o} (before: api=${a}, gw=${n})`),await e.storage.local.set({ipfsApiUrl:s,customGatewayUrl:o,externalNodeConfig:i||[n,a]})):r("useBraveEndpoint: ok")}async function y(e){const[t,i]=(await e.storage.local.get("externalNodeConfig")).externalNodeConfig;r(`releaseBraveEndpoint: restoring api=${i}, gw=${t}`),await e.storage.local.set({ipfsApiUrl:i,customGatewayUrl:t,externalNodeConfig:null})}function _(e){return Array.isArray(e)&&(e=e[0]),o(e,{assumeHttp:!0})}async function w(e,t){for(const i of await e.tabs.query({}))i.url===t&&await e.tabs.remove(i.id)}},7515:(e,t,i)=>{var n=i(3150),a=i(2490),s=i(6566),o=i(8325),l=i(8531);const r="[a-fA-F\\d:]",d=e=>e&&e.includeBoundaries?`(?:(?<=\\s|^)(?=${r})|(?<=${r})(?=\\s|$))`:"",c="(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)(?:\\.(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]\\d|\\d)){3}",p="[a-fA-F\\d]{1,4}",u=`\n(?:\n(?:${p}:){7}(?:${p}|:)|                                    // 1:2:3:4:5:6:7::  1:2:3:4:5:6:7:8\n(?:${p}:){6}(?:${c}|:${p}|:)|                             // 1:2:3:4:5:6::    1:2:3:4:5:6::8   1:2:3:4:5:6::8  1:2:3:4:5:6::1.2.3.4\n(?:${p}:){5}(?::${c}|(?::${p}){1,2}|:)|                   // 1:2:3:4:5::      1:2:3:4:5::7:8   1:2:3:4:5::8    1:2:3:4:5::7:1.2.3.4\n(?:${p}:){4}(?:(?::${p}){0,1}:${c}|(?::${p}){1,3}|:)| // 1:2:3:4::        1:2:3:4::6:7:8   1:2:3:4::8      1:2:3:4::6:7:1.2.3.4\n(?:${p}:){3}(?:(?::${p}){0,2}:${c}|(?::${p}){1,4}|:)| // 1:2:3::          1:2:3::5:6:7:8   1:2:3::8        1:2:3::5:6:7:1.2.3.4\n(?:${p}:){2}(?:(?::${p}){0,3}:${c}|(?::${p}){1,5}|:)| // 1:2::            1:2::4:5:6:7:8   1:2::8          1:2::4:5:6:7:1.2.3.4\n(?:${p}:){1}(?:(?::${p}){0,4}:${c}|(?::${p}){1,6}|:)| // 1::              1::3:4:5:6:7:8   1::8            1::3:4:5:6:7:1.2.3.4\n(?::(?:(?::${p}){0,5}:${c}|(?::${p}){1,7}|:))             // ::2:3:4:5:6:7:8  ::2:3:4:5:6:7:8  ::8             ::1.2.3.4\n)(?:%[0-9a-zA-Z]{1,})?                                             // %eth0            %1\n`.replace(/\s*\/\/.*$/gm,"").replace(/\n/g,"").trim(),g=new RegExp(`(?:^${c}$)|(?:^${u}$)`),f=new RegExp(`^${c}$`),b=new RegExp(`^${u}$`),m=e=>e&&e.exact?g:new RegExp(`(?:${d(e)}${c}${d(e)})|(?:${d(e)}${u}${d(e)})`,"g");m.v4=e=>e&&e.exact?f:new RegExp(`${d(e)}${c}${d(e)}`,"g"),m.v6=e=>e&&e.exact?b:new RegExp(`${d(e)}${u}${d(e)}`,"g");const h=m;var v=i(6028);const{toString:y}=Object.prototype;const _={global:"g",ignoreCase:"i",multiline:"m",dotAll:"s",sticky:"y",unicode:"u"};function w(e,t={}){if(i=e,"[object RegExp]"!==y.call(i))throw new TypeError("Expected a RegExp instance");var i;const n=Object.keys(_).map((i=>("boolean"==typeof t[i]?t[i]:e[i])?_[i]:"")).join(""),a=new RegExp(t.source||e.source,n);return a.lastIndex="number"==typeof t.lastIndex?t.lastIndex:e.lastIndex,a}function $(e,t,{timeout:i}={}){try{return(0,v.Z)((()=>w(e).test(t)),{timeout:i})()}catch(e){if((0,v.q)(e))return!1;throw e}}const R={timeout:400};function M(e){return $(h.v6({exact:!0}),e.slice(0,45),R)}const U=Object.freeze({active:!0,ipfsNodeType:"external",ipfsNodeConfig:JSON.stringify({config:{Addresses:{Swarm:[]}}},null,2),publicGatewayUrl:"https://ipfs.io",publicSubdomainGatewayUrl:"https://dweb.link",useCustomGateway:!0,useSubdomains:!0,enabledOn:[],disabledOn:[],automaticMode:!0,linkify:!1,dnslinkPolicy:"best-effort",dnslinkDataPreload:!0,dnslinkRedirect:!0,recoverFailedHttpRequests:!0,detectIpfsPathHeader:!0,preloadAtPublicGateway:!0,catchUnhandledProtocols:!0,displayNotifications:!0,displayReleaseNotes:!1,customGatewayUrl:"http://localhost:8080",ipfsApiUrl:"http://127.0.0.1:5001",ipfsApiPollMs:3e3,logNamespaces:"jsipfs*,ipfs*,libp2p:mdns*,libp2p-delegated*,-*:ipns*,-ipfs:preload*,-ipfs-http-client:request*,-ipfs:http-api*",importDir:"/ipfs-companion-imports/%Y-%M-%D_%h%m%s/",useLatestWebUI:!1,dismissedUpdate:null,openViaWebUI:!0,telemetryGroupMinimal:!0,telemetryGroupPerformance:!1,telemetryGroupUx:!1,telemetryGroupFeedback:!1,telemetryGroupLocation:!1});function E(e,t){return function(e,t){return t=t||{useLocalhostName:!0},"string"==typeof e&&(e=new URL(e)),"0.0.0.0"===e.hostname&&((e=new URL(e.toString())).hostname="127.0.0.1"),t.useLocalhostName&&O(e)&&(e.hostname="localhost"),!t.useLocalhostName&&P(e)&&(e.hostname="127.0.0.1"),e}(e,t).toString().replace(/\/$/,"")}function x(e){if(l(e)||(t=e,$(h.v4({exact:!0}),t.slice(0,15),R)))return!0;var t;const i=e.match(/^\[(.*)\]$/);return null!=i&&M(i[1])}function k(e){return e=(e=(e=e.map((e=>e.trim().toLowerCase()))).map((e=>{try{return M(e)&&(e=`[${e}]`),new URL(`http://${e}`).hostname}catch(e){return}}))).filter(Boolean).filter(x),(e=[...new Set(e)]).sort(),e}function N(e){return k(e).join("\n")}function S(e){return k(e.split("\n"))}function O(e){return"string"==typeof e&&(e=new URL(e)),"127.0.0.1"===e.hostname||"[::1]"===e.hostname}function P(e){return"string"==typeof e&&(e=new URL(e)),"localhost"===e.hostname.toLowerCase()}var T=i(1536),A=i(9159);var G=i(5356);const L=/^https:\/\/|^http:\/\/localhost|^http:\/\/127.0.0.1|^http:\/\/\[::1\]/;function C({ipfsNodeType:e,customGatewayUrl:t,useCustomGateway:i,useSubdomains:a,disabledOn:o,enabledOn:l,publicGatewayUrl:r,publicSubdomainGatewayUrl:d,onOptionChange:c}){const p=c("customGatewayUrl",(e=>E(e,{useLocalhostName:a}))),u=c("useCustomGateway"),g=c("useSubdomains"),f=c("publicGatewayUrl",E),b=c("publicSubdomainGatewayUrl",E),m=c("disabledOn",S),h=c("enabledOn",S),v=!L.test(t),y=G.DG.includes(e),_="external"===e,w=e===T.braveNodeType?"brave":"";return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_gateways")}</h2>
          <div class="flex-row-ns pb0-ns">
            <label for="publicGatewayUrl">
              <dl>
                <dt>${n.i18n.getMessage("option_publicGatewayUrl_title")}</dt>
                <dd>${n.i18n.getMessage("option_publicGatewayUrl_description")}</dd>
              </dl>
            </label>
            <input
              class="bg-white navy self-center-ns"
              id="publicGatewayUrl"
              type="url"
              inputmode="url"
              required
              pattern="^https?://[^/]+/?$"
              spellcheck="false"
              title="${n.i18n.getMessage("option_hint_url")}"
              onchange=${f}
              value=${r} />
          </div>
          <div class="flex-row-ns pb0-ns">
            <label for="publicSubdomainGatewayUrl">
              <dl>
                <dt>${n.i18n.getMessage("option_publicSubdomainGatewayUrl_title")}</dt>
                <dd>
                  ${n.i18n.getMessage("option_publicSubdomainGatewayUrl_description")}
                  <p><a class="link underline hover-aqua" href="https://docs.ipfs.tech/how-to/address-ipfs-on-web/#subdomain-gateway" target="_blank">
                    ${n.i18n.getMessage("option_legend_readMore")}
                  </a></p>
                </dd>
              </dl>
            </label>
            <input
              class="bg-white navy self-center-ns"
              id="publicSubdomainGatewayUrl"
              type="url"
              inputmode="url"
              required
              pattern="^https?://[^/]+/?$"
              spellcheck="false"
              title="${n.i18n.getMessage("option_hint_url")}"
              onchange=${b}
              value=${d} />
          </div>
          ${y?s`<div class="flex-row-ns pb0-ns">
              <label for="customGatewayUrl">
                <dl>
                  <dt>${n.i18n.getMessage("option_customGatewayUrl_title")}</dt>
                  <dd>${n.i18n.getMessage("option_customGatewayUrl_description")}
                    ${v?s`<p class="red i">${n.i18n.getMessage("option_customGatewayUrl_warning")}</p>`:null}
                  </dd>
                </dl>
              </label>
              <input
                class="bg-white navy self-center-ns ${w}"
                id="customGatewayUrl"
                type="url"
                inputmode="url"
                required
                pattern="^https?://[^/]+/?$"
                spellcheck="false"
                title="${n.i18n.getMessage(_?"option_hint_url":"option_hint_readonly")}"
                onchange=${p}
                ${_?"":"disabled"}
                value=${t} />
            </div>`:null}
          ${y?s`<div class="flex-row-ns pb0-ns">
              <label for="useCustomGateway">
                <dl>
                  <dt>${n.i18n.getMessage("option_useCustomGateway_title")}</dt>
                  <dd>${n.i18n.getMessage("option_useCustomGateway_description")}</dd>
                </dl>
              </label>
              <div class="self-center-ns">${(0,A.Z)({id:"useCustomGateway",checked:i,onchange:u})}</div>
            </div>`:null}
          ${y?s`<div class="flex-row-ns pb0-ns">
              <label for="useSubdomains">
                <dl>
                  <dt>${n.i18n.getMessage("option_useSubdomains_title")}</dt>
                  <dd>
                    ${n.i18n.getMessage("option_useSubdomains_description")}
                    <p><a class="link underline hover-aqua" href="https://docs.ipfs.tech/how-to/address-ipfs-on-web/#subdomain-gateway" target="_blank">
                      ${n.i18n.getMessage("option_legend_readMore")}
                    </a></p>
                  </dd>
                </dl>
              </label>
              <div class="self-center-ns">${(0,A.Z)({id:"useSubdomains",checked:a,onchange:g})}</div>
            </div>`:null}
          ${y?s`<div class="flex-row-ns pb0-ns">
              <label for="disabledOn">
                <dl>
                  <dt>${n.i18n.getMessage("option_disabledOn_title")}</dt>
                  <dd>${n.i18n.getMessage("option_disabledOn_description")}</dd>
                </dl>
              </label>
              <textarea
                class="bg-white navy self-center-ns"
                id="disabledOn"
                spellcheck="false"
                onchange=${m}
                rows="${Math.min(o.length+1,10)}"
                >${N(o)}</textarea>
            </div>
            <div class="flex-row-ns pb0-ns">
              <label for="enabledOn">
                <dl>
                  <dt>${n.i18n.getMessage("option_enabledOn_title")}</dt>
                  <dd>${n.i18n.getMessage("option_enabledOn_description")}</dd>
                </dl>
              </label>
              <textarea
                class="bg-white navy self-center-ns"
                id="enabledOn"
                spellcheck="false"
                onchange=${h}
                rows="${Math.min(l.length+1,10)}"
                >${N(l)}</textarea>
            </div>`:null}

      </fieldset>
    </form>
  `}function I({active:e,onOptionChange:t}){const i=t("active");return s`
    <form class="db b mb3 bg-aqua-muted charcoal">
      <label for="active" class="dib pa3 flex items-center pointer ${e?"":"charcoal bg-gray-muted br2"}">
        ${(0,A.Z)({id:"active",checked:e,onchange:i,style:"mr3"})}
        ${n.i18n.getMessage("panel_headerActiveToggleTitle")}
      </label>
    </form>
  `}function D({emit:e,redirectRules:t}){var i;return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_redirect_rules")}</h2>
        <div class="flex-row-ns pb0-ns">
          <label for="deleteAllRules">
            <dl>
              <dt>
                <div class="self-right-ns">
                  Found ${null!==(i=null==t?void 0:t.length)&&void 0!==i?i:0} rules
                </div>
              </dt>
            </dl>
          </label>
          <div class="self-center-ns">
            <button id="deleteAllRules" class="Button transition-all sans-serif v-mid fw5 nowrap lh-copy bn br1 pa2 pointer focus-outline white bg-red white" onclick=${()=>e("redirectRuleDeleteRequest")}>${n.i18n.getMessage("option_redirect_rules_reset_all")}</button>
          </div>
        </div>
        <div style="max-height: 250px; overflow-y: auto">
          ${t?t.map(function(e){return function({id:t,origin:i,target:a}){return s`
      <div class="flex flex-row-ns pb0-ns">
        <dl class="flex-grow-1">
          <dt>
          <span class="b">${n.i18n.getMessage("option_redirect_rules_row_origin")}:</span> ${i}
          </dt>
          <dt>
          <span class="b">${n.i18n.getMessage("option_redirect_rules_row_target")}:</span> ${a}
          </dt>
        </dl>
        <div class="rule-delete">
          <button class="f6 ph3 pv2 mt0 mb0 bg-transparent b--none red" onclick=${()=>e("redirectRuleDeleteRequest",t)}>X</button>
        </div>
      </div>
    `}}(e)):s`<div>Loading...</div>`}
        </div>
      </fieldset>
    </form>
  `}var q=i(9681);const F=a();F.use((function(e,t){e.options=U;const i=async()=>{const i=await(0,q.Z)(n);e.withNodeFromBrave=i.brave&&await i.brave.getIPFSEnabled(),e.options=await async function(){const e=await n.storage.local.get();return Object.keys(U).reduce(((t,i)=>(t[i]=null==e[i]?U[i]:e[i],t)),{})}(),t.emit("render")};t.on("DOMContentLoaded",(async()=>{n.runtime.sendMessage({telemetry:{trackView:"options"}}),i(),(async()=>{const i=await n.declarativeNetRequest.getDynamicRules();e.redirectRules=i.map((e=>{var t,i;return{id:e.id,origin:null===(t=e.condition.regexFilter)||void 0===t?void 0:t.replace(o.RULE_REGEX_ENDING,"(.*)").replaceAll("\\",""),target:null===(i=e.action.redirect)||void 0===i?void 0:i.regexSubstitution}})),t.emit("render")})(),n.storage.onChanged.addListener(i)})),t.on("redirectRuleDeleteRequest",(async e=>{console.log("delete rule request",e),n.runtime.onMessage.addListener((({type:e})=>{e===o.DELETE_RULE_REQUEST_SUCCESS&&t.emit("render")})),(0,o.notifyDeleteRule)(e)})),t.on("optionChange",(async({key:e,value:t})=>{n.storage.local.set({[e]:t}),await(0,o.notifyOptionChange)()})),t.on("optionsReset",(async()=>{n.storage.local.set(U),await(0,o.notifyOptionChange)()}))})),F.route("*",(function(e,t){const i=(e,i)=>n=>{n.preventDefault();const a="checkbox"===n.target.type?n.target.checked:n.target.value;if(!n.target.reportValidity())return console.warn(`[ipfs-companion] Invalid value for ${e}: ${a}`);t("optionChange",{key:e,value:i?i(a):a}),i&&t("render")};return e.options.active?s`
    <div class="sans-serif">
  ${I({active:e.options.active,onOptionChange:i})}
  ${function({ipfsNodeType:e,onOptionChange:t,withNodeFromBrave:i}){const a=t("ipfsNodeType"),o=e===T.braveNodeType?"brave":"";return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_nodeType")}</h2>
        <div class="flex-row-ns pb0-ns">
          <label for="ipfsNodeType">
            <dl>
              <dt>${n.i18n.getMessage("option_ipfsNodeType_title")}</dt>
              <dd>
                <p>${n.i18n.getMessage("option_ipfsNodeType_external_description")}</p>
                ${i?s`<p>${n.i18n.getMessage("option_ipfsNodeType_brave_description")}</p>`:null}
              </dd>
            </dl>
          </label>
          <select id="ipfsNodeType" name='ipfsNodeType' class="self-center-ns bg-white navy ${o}" onchange=${a}>
            <option
              value='external'
              selected=${"external"===e}>
              ${n.i18n.getMessage("option_ipfsNodeType_external")}
            </option>
            ${i?s`<option
                  value='external:brave'
                  selected=${"external:brave"===e}>
                  ${n.i18n.getMessage("option_ipfsNodeType_brave")}
                </option>`:null}
          </select>
        </div>
      </fieldset>
    </form>
  `}({ipfsNodeType:e.options.ipfsNodeType,ipfsNodeConfig:e.options.ipfsNodeConfig,withNodeFromBrave:e.withNodeFromBrave,onOptionChange:i})}
  ${e.options.ipfsNodeType.startsWith("external")?function({ipfsNodeType:e,ipfsApiUrl:t,ipfsApiPollMs:i,automaticMode:a,onOptionChange:o}){const l=o("ipfsApiUrl",(e=>E(e,{useLocalhostName:!1}))),r=o("ipfsApiPollMs"),d=o("automaticMode"),c="external"===e,p=e===T.braveNodeType?"brave":"";return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_api")}</h2>
        <div class="flex-row-ns pb0-ns">
          <label for="ipfsApiUrl">
            <dl>
              <dt>${n.i18n.getMessage("option_ipfsApiUrl_title")}</dt>
              <dd>${n.i18n.getMessage("option_ipfsApiUrl_description")}</dd>
            </dl>
          </label>
          <input
            class="bg-white navy self-center-ns ${p}"
            id="ipfsApiUrl"
            type="url"
            inputmode="url"
            required
            pattern="^https?://[^/]+/?$"
            spellcheck="false"
            title="${n.i18n.getMessage(c?"option_hint_url":"option_hint_readonly")}"
            onchange=${l}
            ${c?"":"disabled"}
            value=${t} />
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="ipfsApiPollMs">
            <dl>
              <dt>${n.i18n.getMessage("option_ipfsApiPollMs_title")}</dt>
              <dd>${n.i18n.getMessage("option_ipfsApiPollMs_description")}</dd>
            </dl>
          </label>
          <input
            class="bg-white navy self-center-ns"
            id="ipfsApiPollMs"
            type="number"
            inputmode="numeric"
            min="1000"
            max="60000"
            step="1000"
            required
            onchange=${r}
            value=${i} />
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="automaticMode">
            <dl>
              <dt>${n.i18n.getMessage("option_automaticMode_title")}</dt>
              <dd>${n.i18n.getMessage("option_automaticMode_description")}</dd>
              <p class="i">${n.i18n.getMessage("option_automaticMode_description_subtext")}</p>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"automaticMode",checked:a,onchange:d})}</div>
        </div>
      </fieldset>
    </form>
  `}({ipfsNodeType:e.options.ipfsNodeType,ipfsApiUrl:e.options.ipfsApiUrl,ipfsApiPollMs:e.options.ipfsApiPollMs,automaticMode:e.options.automaticMode,onOptionChange:i}):null}
  ${C({ipfsNodeType:e.options.ipfsNodeType,customGatewayUrl:e.options.customGatewayUrl,useCustomGateway:e.options.useCustomGateway,useSubdomains:e.options.useSubdomains,publicGatewayUrl:e.options.publicGatewayUrl,publicSubdomainGatewayUrl:e.options.publicSubdomainGatewayUrl,disabledOn:e.options.disabledOn,enabledOn:e.options.enabledOn,onOptionChange:i})}
  ${function({importDir:e,openViaWebUI:t,preloadAtPublicGateway:i,onOptionChange:a}){const o=a("importDir"),l=a("openViaWebUI"),r=a("preloadAtPublicGateway");return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_fileImport")}</h2>
        <div class="flex-row-ns pb0-ns">
          <label for="importDir">
            <dl>
              <dt>${n.i18n.getMessage("option_importDir_title")}</dt>
              <dd>
                ${n.i18n.getMessage("option_importDir_description")}
                <p><a class="link underline hover-aqua" href="https://docs.ipfs.tech/concepts/file-systems/#mutable-file-system-mfs" target="_blank">
                  ${n.i18n.getMessage("option_legend_readMore")}
                </a></p>
              </dd>
            </dl>
          </label>
          <input
            class="bg-white navy self-center-ns"
            id="importDir"
            type="text"
            pattern="^\/(.*)"
            required
            onchange=${o}
            value=${e} />
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="openViaWebUI">
            <dl>
              <dt>${n.i18n.getMessage("option_openViaWebUI_title")}</dt>
              <dd>${n.i18n.getMessage("option_openViaWebUI_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"openViaWebUI",checked:t,onchange:l})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="preloadAtPublicGateway">
            <dl>
              <dt>${n.i18n.getMessage("option_preloadAtPublicGateway_title")}</dt>
              <dd>${n.i18n.getMessage("option_preloadAtPublicGateway_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"preloadAtPublicGateway",checked:i,onchange:r})}</div>
        </div>
      </fieldset>
    </form>
  `}({importDir:e.options.importDir,openViaWebUI:e.options.openViaWebUI,preloadAtPublicGateway:e.options.preloadAtPublicGateway,onOptionChange:i})}
  ${function({dnslinkPolicy:e,dnslinkDataPreload:t,dnslinkRedirect:i,onOptionChange:a}){const o=a("dnslinkPolicy"),l=a("dnslinkRedirect"),r=a("dnslinkDataPreload");return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_dnslink")}</h2>
        <div class="flex-row-ns pb0-ns">
          <label for="dnslinkPolicy">
            <dl>
              <dt>${n.i18n.getMessage("option_dnslinkPolicy_title")}</dt>
              <dd>
                ${n.i18n.getMessage("option_dnslinkPolicy_description")}
                <p><a class="link underline hover-aqua" href="https://docs.ipfs.tech/how-to/dnslink-companion/" target="_blank">
                  ${n.i18n.getMessage("option_legend_readMore")}
                </a></p>
              </dd>
            </dl>
          </label>
          <select id="dnslinkPolicy" name='dnslinkPolicy' class="self-center-ns bg-white navy" onchange=${o}>
            <option
              value='false'
              selected=${"false"===String(e)}>
              ${n.i18n.getMessage("option_dnslinkPolicy_disabled")}
            </option>
            <option
              value='best-effort'
              selected=${"best-effort"===e}>
              ${n.i18n.getMessage("option_dnslinkPolicy_bestEffort")}
            </option>
            <option
              value='enabled'
              selected=${"enabled"===e}>
              ${n.i18n.getMessage("option_dnslinkPolicy_enabled")}
            </option>
          </select>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="dnslinkDataPreload">
            <dl>
              <dt>${n.i18n.getMessage("option_dnslinkDataPreload_title")}</dt>
              <dd>${n.i18n.getMessage("option_dnslinkDataPreload_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"dnslinkDataPreload",checked:t,disabled:i,onchange:r})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="dnslinkRedirect">
            <dl>
              <dt>${n.i18n.getMessage("option_dnslinkRedirect_title")}</dt>
              <dd>
                ${n.i18n.getMessage("option_dnslinkRedirect_description")}
                ${i?s`<p class="red i">${n.i18n.getMessage("option_dnslinkRedirect_warning")}</p>`:null}
                <p><a class="link underline hover-aqua" href="https://docs.ipfs.tech/how-to/address-ipfs-on-web/#subdomain-gateway" target="_blank">
                  ${n.i18n.getMessage("option_legend_readMore")}
                </a></p>
              </dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"dnslinkRedirect",checked:i,onchange:l})}</div>
        </div>
      </fieldset>
    </form>
  `}({dnslinkPolicy:e.options.dnslinkPolicy,dnslinkDataPreload:e.options.dnslinkDataPreload,dnslinkRedirect:e.options.dnslinkRedirect,onOptionChange:i})}
  ${function({useLatestWebUI:e,displayNotifications:t,displayReleaseNotes:i,catchUnhandledProtocols:a,linkify:o,recoverFailedHttpRequests:l,detectIpfsPathHeader:r,logNamespaces:d,onOptionChange:c}){const p=c("displayNotifications"),u=c("displayReleaseNotes"),g=c("useLatestWebUI"),f=c("catchUnhandledProtocols"),b=c("linkify"),m=c("recoverFailedHttpRequests"),h=c("detectIpfsPathHeader");return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_experiments")}</h2>
        <div class="mb2">${n.i18n.getMessage("option_experiments_warning")}</div>
        <div class="flex-row-ns pb0-ns">
          <label for="useLatestWebUI">
            <dl>
              <dt>${n.i18n.getMessage("option_useLatestWebUI_title")}</dt>
              <dd>${n.i18n.getMessage("option_useLatestWebUI_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"useLatestWebUI",checked:e,onchange:g})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="displayNotifications">
            <dl>
              <dt>${n.i18n.getMessage("option_displayNotifications_title")}</dt>
              <dd>${n.i18n.getMessage("option_displayNotifications_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"displayNotifications",checked:t,onchange:p})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="displayReleaseNotes">
            <dl>
              <dt>${n.i18n.getMessage("option_displayReleaseNotes_title")}</dt>
              <dd>${n.i18n.getMessage("option_displayReleaseNotes_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"displayReleaseNotes",checked:i,onchange:u})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="catchUnhandledProtocols">
            <dl>
              <dt>${n.i18n.getMessage("option_catchUnhandledProtocols_title")}</dt>
              <dd>${n.i18n.getMessage("option_catchUnhandledProtocols_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"catchUnhandledProtocols",checked:a,onchange:f})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="recoverFailedHttpRequests">
            <dl>
              <dt>${n.i18n.getMessage("option_recoverFailedHttpRequests_title")}</dt>
              <dd>${n.i18n.getMessage("option_recoverFailedHttpRequests_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"recoverFailedHttpRequests",checked:l,onchange:m})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="linkify">
            <dl>
              <dt>${n.i18n.getMessage("option_linkify_title")}</dt>
              <dd>${n.i18n.getMessage("option_linkify_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"linkify",checked:o,onchange:b})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="detectIpfsPathHeader">
            <dl>
              <dt>${n.i18n.getMessage("option_detectIpfsPathHeader_title")}</dt>
              <dd>${n.i18n.getMessage("option_detectIpfsPathHeader_description")}
                <p><a class="link underline hover-aqua" href="https://docs.ipfs.tech/how-to/companion-x-ipfs-path-header/" target="_blank">
                  ${n.i18n.getMessage("option_legend_readMore")}
                </a></p>
              </dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"detectIpfsPathHeader",checked:r,onchange:h})}</div>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="logNamespaces">
            <dl>
              <dt>${n.i18n.getMessage("option_logNamespaces_title")}</dt>
              <dd>${n.i18n.getMessage("option_logNamespaces_description")}</dd>
            </dl>
          </label>
          <input
            class="bg-white navy self-center-ns"
            id="logNamespaces"
            type="text"
            required
            onchange=${c("logNamespaces")}
            value=${d} />
        </div>
      </fieldset>
    </form>
  `}({useLatestWebUI:e.options.useLatestWebUI,displayNotifications:e.options.displayNotifications,displayReleaseNotes:e.options.displayReleaseNotes,catchUnhandledProtocols:e.options.catchUnhandledProtocols,linkify:e.options.linkify,recoverFailedHttpRequests:e.options.recoverFailedHttpRequests,detectIpfsPathHeader:e.options.detectIpfsPathHeader,logNamespaces:e.options.logNamespaces,onOptionChange:i})}
  ${function({onOptionChange:e,...t}){return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_telemetry")}</h2>
        <div class="mb2">
          <p>${n.i18n.getMessage("option_telemetry_disclaimer")}</p>
          <p>
            <a class="link underline hover-aqua" href="https://github.com/ipfs-shipyard/ignite-metrics/blob/main/docs/telemetry/COLLECTION_POLICY.md" target="_blank">
              ${n.i18n.getMessage("option_legend_readMore")}
            </a>
          </p>
        </div>
        <div class="flex-row-ns pb0-ns">
          <label for="telemetryGroupMinimal">
            <dl>
              <dt>${n.i18n.getMessage("option_telemetryGroupMinimal_title")}</dt>
              <dd>
                <p>${n.i18n.getMessage("option_telemetryGroupMinimal_description")}</p>
              </dd>
            </dl>
          </label>
          <div class="self-center-ns">${(0,A.Z)({id:"telemetryGroupMinimal",checked:t.telemetryGroupMinimal,onchange:e("telemetryGroupMinimal")})}</div>
        </div>
      </fieldset>
    </form>
  `}({telemetryGroupMinimal:e.options.telemetryGroupMinimal,telemetryGroupMarketing:e.options.telemetryGroupMarketing,telemetryGroupPerformance:e.options.telemetryGroupPerformance,telemetryGroupTracking:e.options.telemetryGroupTracking,onOptionChange:i})}
  ${function({onOptionsReset:e}){return s`
    <form>
      <fieldset class="mb3 pa1 pa4-ns pa3 bg-snow-muted charcoal">
        <h2 class="ttu tracked f6 fw4 teal mt0-ns mb3-ns mb1 mt2 ">${n.i18n.getMessage("option_header_reset")}</h2>
        <div class="flex-row-ns pb0-ns">
          <label for="resetAllOptions">
            <dl>
              <dt>${n.i18n.getMessage("option_resetAllOptions_title")}</dt>
              <dd>${n.i18n.getMessage("option_resetAllOptions_description")}</dd>
            </dl>
          </label>
          <div class="self-center-ns"><button id="resetAllOptions" class="Button transition-all sans-serif v-mid fw5 nowrap lh-copy bn br1 pa2 pointer focus-outline white bg-red white" onclick=${e}>${n.i18n.getMessage("option_resetAllOptions_title")}</button></div>
        </div>
      </fieldset>
    </form>
  `}({onOptionsReset:e=>{e.preventDefault(),t("optionsReset")}})}
  ${(0,o.supportsDeclarativeNetRequest)()?D({redirectRules:e.redirectRules,emit:t}):""}
    </div>
  `:s`
    <div class="sans-serif">
      ${I({active:e.options.active,onOptionChange:i})}
    </div>
    `})),F.mount("#root"),document.getElementById("header-text").innerText=n.i18n.getMessage("option_page_header"),document.title=n.i18n.getMessage("option_page_title")}},i={};function n(e){var a=i[e];if(void 0!==a)return a.exports;var s=i[e]={exports:{}};return t[e].call(s.exports,s,s.exports,n),s.exports}n.m=t,e=[],n.O=(t,i,a,s)=>{if(!i){var o=1/0;for(c=0;c<e.length;c++){for(var[i,a,s]=e[c],l=!0,r=0;r<i.length;r++)(!1&s||o>=s)&&Object.keys(n.O).every((e=>n.O[e](i[r])))?i.splice(r--,1):(l=!1,s<o&&(o=s));if(l){e.splice(c--,1);var d=a();void 0!==d&&(t=d)}}return t}s=s||0;for(var c=e.length;c>0&&e[c-1][2]>s;c--)e[c]=e[c-1];e[c]=[i,a,s]},n.d=(e,t)=>{for(var i in t)n.o(t,i)&&!n.o(e,i)&&Object.defineProperty(e,i,{enumerable:!0,get:t[i]})},n.o=(e,t)=>Object.prototype.hasOwnProperty.call(e,t),n.r=e=>{"undefined"!=typeof Symbol&&Symbol.toStringTag&&Object.defineProperty(e,Symbol.toStringTag,{value:"Module"}),Object.defineProperty(e,"__esModule",{value:!0})},n.j=407,(()=>{var e={407:0};n.O.j=t=>0===e[t];var t=(t,i)=>{var a,s,[o,l,r]=i,d=0;if(o.some((t=>0!==e[t]))){for(a in l)n.o(l,a)&&(n.m[a]=l[a]);if(r)var c=r(n)}for(t&&t(i);d<o.length;d++)s=o[d],n.o(e,s)&&e[s]&&e[s][0](),e[s]=0;return n.O(c)},i=self.webpackChunkipfs_companion=self.webpackChunkipfs_companion||[];i.forEach(t.bind(null,0)),i.push=t.bind(null,i.push.bind(i))})();var a=n.O(void 0,[297],(()=>n(7515)));a=n.O(a)})();