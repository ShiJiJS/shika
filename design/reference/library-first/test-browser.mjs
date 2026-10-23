import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.VIDEO_VIEWER_PLAYWRIGHT||'playwright');
const browserOptions={headless:true,...(process.env.VIDEO_VIEWER_BROWSER?{executablePath:process.env.VIDEO_VIEWER_BROWSER}:{})};
export {chromium,browserOptions};
