-- SkyborneData.lua: the Skyborne spots every player starts with: { uiMapID, x, y }, in percent.
-- Data from tr0tsky's Skyborne Ley Line & Convergence Marker v0.2.3 (https://www.curseforge.com/wow/addons/sllcm):
-- MIT License. Copyright (c) 2026 tr0tsky
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this
-- software and associated documentation files (the "Software"), to deal in the Software
-- without restriction, including without limitation the rights to use, copy, modify, merge,
-- publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
-- to whom the Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or
-- substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
-- PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
-- FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
-- OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.
local ns = _G.NaowhForever

ns.SkyborneSpots = {
    leyline = {
        { 1416, 19.9, 86.1 },
        { 1417, 25.3, 30 },
        { 1417, 48, 60.5 },
        { 1426, 56.6, 45.6 },
        { 1426, 63.8, 50.7 },
        { 1428, 78.6, 61.8 },
        { 1429, 64.93, 67.32 },
        { 1429, 27.42, 94.27 },
        { 1429, 37.32, 55.55 },
        { 1429, 75.25, 51.95 },
        { 1431, 18.7, 57.2 },
        { 1431, 72.5, 30.6 },
        { 1433, 12.6, 72.8 },
        { 1433, 30.97, 46.11 },
        { 1436, 35.05, 72.98 },
        { 1436, 59.8, 31.5 },
        { 1436, 51.1, 67.5 },
        { 1436, 51.3, 22.46 },
        { 1436, 41.91, 83.29 },
        { 1439, 57.58, 26.62 },
        { 1439, 60.44, 19.48 },
        { 1439, 35.98, 86.22 },
        { 1439, 42.81, 59.84 },
        { 2521, 58.8, 33.5 },
        { 2521, 63.9, 74.1 },
        { 2521, 45.5, 81.31 },
        { 2521, 47.99, 59.1 },
        { 2521, 38.39, 47.58 },
        { 2521, 35.28, 33.68 },
        { 2521, 46.03, 18.08 },
        { 2521, 50.31, 33.18 },
        { 2521, 54.97, 50.41 },
        { 2521, 63.73, 45.94 },
        { 2521, 68.85, 61.88 },
        { 2521, 53.8, 66.3 },
        { 2521, 33.8, 55.5 },
    },
    convergence = {
        { 1411, 45.12, 15.7 },
        { 1411, 53.17, 16.15 },
        { 1412, 38.61, 44.73 },
        { 1412, 50.61, 52.94 },
        { 1413, 54.02, 26.59 },
        { 1413, 43.58, 42.15 },
        { 1413, 44.79, 54.97 },
        { 1413, 49.67, 34.58 },
        { 1413, 48.5, 46.29 },
        { 1413, 49.07, 15.47 },
        { 1413, 54.82, 34.73 },
        { 1417, 52.05, 50.7 },
        { 1437, 60.2, 56.98 },
        { 1441, 42.19, 49.47 },
        { 1442, 74.84, 94.43 },
        { 2521, 48.44, 20.31 },
        { 2521, 35.93, 33.68 },
        { 2521, 46.59, 38.24 },
        { 2521, 34.07, 59.83 },
        { 2521, 48.5, 55.81 },
        { 2521, 52.85, 57.52 },
        { 2521, 47.64, 69.54 },
        { 2521, 59.14, 79.81 },
        { 2521, 61.59, 51.53 },
        { 2521, 68.36, 66.04 },
        { 2521, 64.85, 38.02 },
        { 2521, 67.51, 50.54 },
        { 2521, 48.39, 80.64 },
        { 2521, 67.89, 74.94 },
        { 2521, 70.04, 61.41 },
    },
}
