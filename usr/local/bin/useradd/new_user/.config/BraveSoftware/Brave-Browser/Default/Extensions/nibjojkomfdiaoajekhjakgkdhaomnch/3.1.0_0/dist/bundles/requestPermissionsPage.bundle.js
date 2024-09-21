(()=>{"use strict";var e,s={4114:(e,s,r)=>{var n=r(2490),t=r(6566),i=r(3150),a=r(2633),o=r(1991),l=r(8583);const p=n(),u=t`<a class="navy link underline-under hover-aqua" href="https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/host_permissions#requested_permissions_and_user_prompts" target="_blank" rel="noopener noreferrer">${i.i18n.getMessage("request_permissions_page_learn_more")}</a>`,f=t`<a class="navy link underline-under hover-aqua" id="learn-more" href="${l.hO}" target="_blank" rel="noopener noreferrer">${i.i18n.getMessage("recovery_page_update_preferences")}</a>`;p.use((0,o.Z)(i.i18n,i.runtime)),p.route("*",(()=>{i.runtime.sendMessage({telemetry:{trackView:"request-permissions"}});return t`<div class="flex flex-column flex-row-l">
    <div id="left-col" class="min-vh-100 flex flex-column justify-center items-center bg-navy white">
      <div class="mb4 flex flex-column justify-center items-center">
        ${(0,a.$I)(200)}
        <p class="mt0 mb0 f3 tc">${i.i18n.getMessage("request_permissions_page_sub_header")}</p>
      </div>
    </div>

    <div id="right-col" class="pt7 mt5 w-100 flex flex-column justify-around items-center">
      <p class="f3 fw5">${i.i18n.getMessage("request_permissions_page_message_p1")}</p>
      <p class="f4 fw4">${i.i18n.getMessage("request_permissions_page_message_p2")}</p>
      <button
        class="fade-in ba bw1 b--teal bg-teal snow f7 ph2 pv3 br2 ma4 pointer"
        onclick=${async()=>{await i.permissions.request({origins:["<all_urls>"]}),i.runtime.reload()}}
      >
        <span class="f5 fw6">${i.i18n.getMessage("request_permissions_page_button")}</span>
      </button>
      <p class="f5 fw2 pt5">
        ${u} | ${f}
      </span>
    </div>
  </div>`})),p.mount("#root"),document.title=i.i18n.getMessage("request_permissions_page_title")}},r={};function n(e){var t=r[e];if(void 0!==t)return t.exports;var i=r[e]={exports:{}};return s[e].call(i.exports,i,i.exports,n),i.exports}n.m=s,e=[],n.O=(s,r,t,i)=>{if(!r){var a=1/0;for(u=0;u<e.length;u++){for(var[r,t,i]=e[u],o=!0,l=0;l<r.length;l++)(!1&i||a>=i)&&Object.keys(n.O).every((e=>n.O[e](r[l])))?r.splice(l--,1):(o=!1,i<a&&(a=i));if(o){e.splice(u--,1);var p=t();void 0!==p&&(s=p)}}return s}i=i||0;for(var u=e.length;u>0&&e[u-1][2]>i;u--)e[u]=e[u-1];e[u]=[r,t,i]},n.d=(e,s)=>{for(var r in s)n.o(s,r)&&!n.o(e,r)&&Object.defineProperty(e,r,{enumerable:!0,get:s[r]})},n.o=(e,s)=>Object.prototype.hasOwnProperty.call(e,s),n.r=e=>{"undefined"!=typeof Symbol&&Symbol.toStringTag&&Object.defineProperty(e,Symbol.toStringTag,{value:"Module"}),Object.defineProperty(e,"__esModule",{value:!0})},n.j=577,(()=>{var e={577:0};n.O.j=s=>0===e[s];var s=(s,r)=>{var t,i,[a,o,l]=r,p=0;if(a.some((s=>0!==e[s]))){for(t in o)n.o(o,t)&&(n.m[t]=o[t]);if(l)var u=l(n)}for(s&&s(r);p<a.length;p++)i=a[p],n.o(e,i)&&e[i]&&e[i][0](),e[i]=0;return n.O(u)},r=self.webpackChunkipfs_companion=self.webpackChunkipfs_companion||[];r.forEach(s.bind(null,0)),r.push=s.bind(null,r.push.bind(r))})();var t=n.O(void 0,[297],(()=>n(4114)));t=n.O(t)})();