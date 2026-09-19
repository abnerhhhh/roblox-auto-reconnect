#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wincodec.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <iostream>
#include <thread>

using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

struct WindowSearch { DWORD pid; HWND hwnd = nullptr; };

BOOL CALLBACK FindWindow(HWND hwnd, LPARAM data) {
    auto& search = *reinterpret_cast<WindowSearch*>(data);
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    if (pid != search.pid || !IsWindowVisible(hwnd) || GetWindow(hwnd, GW_OWNER)) return TRUE;
    RECT rect{};
    if (!GetWindowRect(hwnd, &rect) || rect.right <= rect.left || rect.bottom <= rect.top) return TRUE;
    search.hwnd = hwnd;
    return FALSE;
}

void SavePng(ID3D11Device* device, ID3D11Texture2D* source, const wchar_t* path) {
    D3D11_TEXTURE2D_DESC desc{};
    source->GetDesc(&desc);
    if (!desc.Width || !desc.Height || desc.Width > 16384 || desc.Height > 16384)
        throw hresult_error(E_INVALIDARG);
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags = 0;
    com_ptr<ID3D11Texture2D> staging;
    check_hresult(device->CreateTexture2D(&desc, nullptr, staging.put()));
    com_ptr<ID3D11DeviceContext> context;
    device->GetImmediateContext(context.put());
    context->CopyResource(staging.get(), source);
    D3D11_MAPPED_SUBRESOURCE mapped{};
    check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
    try {
        // A failed GPU capture can contain an all-black or fully transparent frame.
        bool nonblank = false;
        for (UINT y = 0; y < desc.Height && !nonblank; y += 8) {
            auto row = static_cast<const BYTE*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch;
            for (UINT x = 0; x < desc.Width; x += 8) {
                auto pixel = row + static_cast<size_t>(x) * 4;
                if (pixel[3] && (pixel[0] || pixel[1] || pixel[2])) { nonblank = true; break; }
            }
        }
        if (!nonblank) throw hresult_error(E_FAIL);
        com_ptr<IWICImagingFactory> factory;
        check_hresult(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(factory.put())));
        com_ptr<IWICStream> stream;
        check_hresult(factory->CreateStream(stream.put()));
        check_hresult(stream->InitializeFromFilename(path, GENERIC_WRITE));
        com_ptr<IWICBitmapEncoder> encoder;
        check_hresult(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.put()));
        check_hresult(encoder->Initialize(stream.get(), WICBitmapEncoderNoCache));
        com_ptr<IWICBitmapFrameEncode> frame;
        com_ptr<IPropertyBag2> options;
        check_hresult(encoder->CreateNewFrame(frame.put(), options.put()));
        check_hresult(frame->Initialize(options.get()));
        check_hresult(frame->SetSize(desc.Width, desc.Height));
        auto pixelFormat = GUID_WICPixelFormat32bppBGRA;
        check_hresult(frame->SetPixelFormat(&pixelFormat));
        if (pixelFormat != GUID_WICPixelFormat32bppBGRA) throw hresult_error(E_FAIL);
        check_hresult(frame->WritePixels(desc.Height, mapped.RowPitch,
            mapped.RowPitch * desc.Height, static_cast<BYTE*>(mapped.pData)));
        check_hresult(frame->Commit());
        check_hresult(encoder->Commit());
    } catch (...) {
        context->Unmap(staging.get(), 0);
        throw;
    }
    context->Unmap(staging.get(), 0);
}

int wmain(int argc, wchar_t** argv) {
    if (argc != 3) return 2;
    bool selfTest = wcscmp(argv[1], L"--self-test") == 0;
    WindowSearch search{};
    if (selfTest) {
        WNDCLASSW green{};
        green.lpfnWndProc = DefWindowProcW;
        green.hInstance = GetModuleHandleW(nullptr);
        green.lpszClassName = L"RobloxReconnectGreenCaptureTest";
        green.hbrBackground = CreateSolidBrush(RGB(0, 200, 0));
        RegisterClassW(&green);
        search.hwnd = CreateWindowW(green.lpszClassName, L"Capture test target",
            WS_OVERLAPPEDWINDOW | WS_VISIBLE, 50, 50, 480, 300,
            nullptr, nullptr, green.hInstance, nullptr);
        WNDCLASSW red = green;
        red.lpszClassName = L"RobloxReconnectRedCaptureCover";
        red.hbrBackground = CreateSolidBrush(RGB(200, 0, 0));
        RegisterClassW(&red);
        CreateWindowW(red.lpszClassName, L"Capture test cover",
            WS_OVERLAPPEDWINDOW | WS_VISIBLE, 50, 50, 480, 300,
            nullptr, nullptr, red.hInstance, nullptr);
        UpdateWindow(search.hwnd);
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
    } else {
        DWORD pid = wcstoul(argv[1], nullptr, 10);
        if (!pid) return 2;
        search.pid = pid;
        EnumWindows(FindWindow, reinterpret_cast<LPARAM>(&search));
    }
    if (!search.hwnd || IsIconic(search.hwnd)) return 3;
    try {
        init_apartment(apartment_type::multi_threaded);
        com_ptr<ID3D11Device> d3d;
        UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        auto hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
            nullptr, 0, D3D11_SDK_VERSION, d3d.put(), nullptr, nullptr);
        if (FAILED(hr)) check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
            flags, nullptr, 0, D3D11_SDK_VERSION, d3d.put(), nullptr, nullptr));
        auto dxgi = d3d.as<IDXGIDevice>();
        com_ptr<IInspectable> inspectable;
        check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.get(), inspectable.put()));
        auto device = inspectable.as<IDirect3DDevice>();
        auto factory = get_activation_factory<GraphicsCaptureItem>().as<IGraphicsCaptureItemInterop>();
        GraphicsCaptureItem item{nullptr};
        check_hresult(factory->CreateForWindow(search.hwnd,
            guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
            reinterpret_cast<void**>(put_abi(item))));
        auto pool = Direct3D11CaptureFramePool::CreateFreeThreaded(device,
            DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, item.Size());
        auto session = pool.CreateCaptureSession(item);
        std::mutex mutex;
        std::condition_variable ready;
        Direct3D11CaptureFrame captured{nullptr};
        auto token = pool.FrameArrived([&](auto const& sender, auto const&) {
            auto next = sender.TryGetNextFrame();
            std::lock_guard guard(mutex);
            if (!captured) { captured = next; ready.notify_one(); }
        });
        session.StartCapture();
        {
            std::unique_lock lock(mutex);
            if (!ready.wait_for(lock, std::chrono::seconds(5), [&] { return static_cast<bool>(captured); }))
                return 4;
        }
        auto access = captured.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
        com_ptr<ID3D11Texture2D> texture;
        check_hresult(access->GetInterface(IID_PPV_ARGS(texture.put())));
        SavePng(d3d.get(), texture.get(), argv[2]);
        pool.FrameArrived(token);
        session.Close();
        pool.Close();
        return 0;
    } catch (hresult_error const& e) {
        std::wcerr << L"Capture failed: 0x" << std::hex << static_cast<unsigned>(e.code().value) << L'\n';
        return 5;
    } catch (...) {
        return 5;
    }
}
