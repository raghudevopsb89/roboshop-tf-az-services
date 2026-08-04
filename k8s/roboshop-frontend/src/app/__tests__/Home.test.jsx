import { render, screen, waitFor } from '@testing-library/react';
import Home from '../page';

describe('Home page', () => {
    beforeEach(() => {
        global.fetch = jest.fn(() =>
            Promise.resolve({
                json: () =>
                    Promise.resolve([
                        {
                            id: 1,
                            name: 'Servo Motor',
                            category: 'Actuators',
                            description: 'A precise servo',
                            price: 25,
                            imageUrl: '/servo.png',
                        },
                    ]),
            })
        );
    });

    afterEach(() => {
        jest.resetAllMocks();
    });

    it('renders the hero heading and browse link without crashing', () => {
        render(<Home />);
        expect(
            screen.getByRole('heading', { name: /welcome to roboshop/i })
        ).toBeInTheDocument();
        const link = screen.getByRole('link', { name: /browse catalogue/i });
        expect(link).toHaveAttribute('href', '/catalogue');
    });

    it('fetches products from the catalogue endpoint on mount', async () => {
        render(<Home />);
        await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
        expect(global.fetch).toHaveBeenCalledWith('/api/catalogue/products');
    });

    it('renders fetched products in the featured grid', async () => {
        render(<Home />);
        expect(await screen.findByText('Servo Motor')).toBeInTheDocument();
        expect(screen.getByText('$25')).toBeInTheDocument();
        // Category badge and details link derived from product data
        expect(screen.getByText('Actuators')).toBeInTheDocument();
        expect(
            screen.getByRole('link', { name: /view details/i })
        ).toHaveAttribute('href', '/product/1');
    });
});
